#!/usr/bin/env python3
"""Create or update a Loady user in the local Cosmos emulator so a real DEV B2C token resolves.

Use case: running Loady.Backend.Api with DEV authentication but local databases (the
`be-backend-sso` and `stack-be-fe-sso` run configurations in dotfiles/rider/run/). Token
validation succeeds against DEV
B2C, then the backend resolves the Loady user by normalized email against local Cosmos, where every
seeded user is @testcompany1.loc or @testcompany2.loc. Without a matching local user every
authenticated request returns 401.

The email written here must match the token's `emails` claim after normalization (lowercased,
trimmed). Idempotent: a second run updates the existing user rather than adding a duplicate.

The backend caches UserData and UserDto by mail, so the local Redis database is flushed at the end.

The Cosmos key below is the emulator's documented public one, not a credential.

Usage:
    ld-user [email] [--company TESTCOMPANY1] [--role companyAdmin] [--id <guid>]

The email defaults to the checkout's `git config user.email`. The user id defaults to a
deterministic GUID derived from the email, so the same email always lands on the same document.

Run it on the VM: Cosmos and Redis are the containers ld-reset starts there. From the Mac,
`ld-vm ld-user`.
"""

import argparse
import base64
import datetime
import hashlib
import hmac
import json
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

EMULATOR_KEY = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
HOST = "https://localhost:8081"
DATABASE = "Loady"
REDIS_HOST = "127.0.0.1"
REDIS_PORT = "6379"
REDIS_CONTAINER = "redis"

# The emulator serves a self-signed certificate. scripts/cosmos-cert.sh puts it in the system trust
# store for everything else, but Python carries its own bundle and would not see it.
CONTEXT = ssl.create_default_context()
CONTEXT.check_hostname = False
CONTEXT.verify_mode = ssl.CERT_NONE


def authorization(verb, resource_type, resource_link, date):
    payload = f"{verb.lower()}\n{resource_type.lower()}\n{resource_link}\n{date.lower()}\n\n"
    signature = base64.b64encode(
        hmac.new(base64.b64decode(EMULATOR_KEY), payload.encode("utf-8"), hashlib.sha256).digest()
    ).decode()
    return urllib.parse.quote(f"type=master&ver=1.0&sig={signature}", safe="")


def send(collection, body, extra_headers):
    resource_link = f"dbs/{DATABASE}/colls/{collection}"
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
    headers = {
        "Authorization": authorization("POST", "docs", resource_link, date),
        "x-ms-date": date,
        "x-ms-version": "2018-12-31",
        "Content-Type": "application/json",
    }
    headers.update(extra_headers)
    request = urllib.request.Request(
        f"{HOST}/{resource_link}/docs",
        data=json.dumps(body).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, context=CONTEXT, timeout=30) as response:
        return json.loads(response.read())


def query(collection, sql, parameters=None):
    body = {"query": sql, "parameters": parameters or []}
    return send(collection, body, {
        "Content-Type": "application/query+json",
        "x-ms-documentdb-isquery": "true",
        "x-ms-documentdb-query-enablecrosspartition": "true",
    })["Documents"]


def upsert(collection, document):
    return send(collection, document, {
        "x-ms-documentdb-is-upsert": "true",
        "x-ms-documentdb-partitionkey": json.dumps([document["id"]]),
    })


def git_email():
    try:
        result = subprocess.run(
            ["git", "config", "--get", "user.email"],
            capture_output=True, text=True, timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def flush_redis():
    # redis-cli is not installed on the VM and does not need to be: Redis is the container
    # compose/loady-vm.yaml names `redis`. A host redis-cli is used when there is one, which keeps
    # this working anywhere the port is reachable.
    attempts = [
        ["redis-cli", "-h", REDIS_HOST, "-p", REDIS_PORT, "FLUSHDB"],
        ["docker", "exec", REDIS_CONTAINER, "redis-cli", "FLUSHDB"],
    ]
    failures = []
    for command in attempts:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=15)
        except FileNotFoundError:
            failures.append(f"{command[0]} is not installed")
            continue
        except subprocess.TimeoutExpired:
            failures.append(f"{command[0]} timed out")
            continue
        if result.returncode == 0:
            print(f"==> flushed Redis via {command[0]}")
            return
        failures.append(f"{command[0]}: {(result.stderr or result.stdout).strip()}")

    print(f"ld-user: could not flush Redis ({'; '.join(failures)})", file=sys.stderr)
    print("         restart the backend, or the cached 401 survives this", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        prog="ld-user",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("email", nargs="?", help="defaults to git config user.email")
    parser.add_argument("--company", default="TESTCOMPANY1", help="companyLoadyId (default: TESTCOMPANY1)")
    parser.add_argument("--role", default="companyAdmin", help="roleId (default: companyAdmin)")
    parser.add_argument("--id", dest="user_id", help="user id (default: derived from the email)")
    arguments = parser.parse_args()

    email = (arguments.email or git_email()).strip().lower()
    if not email:
        parser.error("no email given and git config user.email is not set")
    if "@" not in email:
        parser.error(f"'{email}' is not an email address")

    company = arguments.company
    user_id = arguments.user_id or str(uuid.uuid5(uuid.NAMESPACE_URL, f"loady-local:{email}"))

    first_name = email.split("@", 1)[0].split(".")[0].capitalize() or "Local"
    last_name = "SsoTest"
    now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

    existing = query("Users", "SELECT c.id FROM c WHERE c.mail = @mail", [{"name": "@mail", "value": email}])
    if existing:
        user_id = existing[0]["id"]
        print(f"==> updating existing user {user_id}")
    else:
        print(f"==> creating user {user_id}")

    upsert("Users", {
        "id": user_id,
        "type": "UserData",
        "mail": email,
        "firstName": first_name,
        "lastName": last_name,
        "roles": [{"companyId": company, "roleId": arguments.role}],
        "invitationAccepted": True,
        "createdBy": "LocalSsoSetup",
        "createdByUserName": "Local SSO Setup",
        "updatedBy": "LocalSsoSetup",
        "updatedByUserName": "Local SSO Setup",
        "createdTimeUtc": now,
        "updatedTimeUtc": now,
    })

    members_documents = query(
        "CompanyMembers",
        "SELECT * FROM c WHERE c.id = @companyId",
        [{"name": "@companyId", "value": company}],
    )
    if not members_documents:
        print(f"ld-user: no CompanyMembers document for '{company}'; run ld-reset to seed", file=sys.stderr)
        return 1

    document = {key: value for key, value in members_documents[0].items() if not key.startswith("_")}
    members = [member for member in document.get("members", []) if member.get("mail", "").lower() != email]
    members.append({
        "id": user_id,
        "firstName": first_name,
        "lastName": last_name,
        "mail": email,
        "roleId": arguments.role,
    })
    document["members"] = members
    upsert("CompanyMembers", document)

    print(f"==> {email} -> {company} as {arguments.role} (userId {user_id})")
    flush_redis()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except urllib.error.URLError as error:
        print(f"ld-user: cannot reach the Cosmos emulator at {HOST}: {error.reason}", file=sys.stderr)
        print("         run it on the VM, and run ld-reset if the containers are not up", file=sys.stderr)
        sys.exit(1)
