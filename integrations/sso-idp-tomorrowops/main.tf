resource "azuread_application" "oidc" {
  display_name            = var.application_display_name
  prevent_duplicate_names = true
  sign_in_audience        = "AzureADMyOrg"

  web {
    redirect_uris = [var.b2c_callback_url]

    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }

  # given_name/family_name are not included in a v2.0 ID token just because the "profile" scope was requested -
  # Entra only emits them if the app registration explicitly asks for them as optional claims.
  optional_claims {
    id_token {
      name = "given_name"
    }

    id_token {
      name = "family_name"
    }
  }
}

resource "azuread_service_principal" "oidc" {
  client_id                    = azuread_application.oidc.client_id
  app_role_assignment_required = false
}

resource "azuread_application_password" "oidc" {
  application_id = azuread_application.oidc.id
  display_name   = "Loady B2C OIDC"
  end_date       = var.client_secret_end_date
}

resource "azuread_user" "test" {
  for_each = nonsensitive(toset(keys(var.test_users)))

  user_principal_name   = each.key
  display_name          = var.test_users[each.key].display_name
  given_name            = var.test_users[each.key].given_name
  surname               = var.test_users[each.key].surname
  password              = var.test_users[each.key].password
  force_password_change = var.test_users[each.key].force_password_change
}
