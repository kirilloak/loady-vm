output "ipv4_address" {
  description = "The static address; the Mac's /etc/hosts entry points at it"
  value       = local.ipv4_address
}

output "bootstrap_log" {
  description = "Stable path to the latest bootstrap log inside the VM"
  value       = "/home/dev/.local/state/loady-vm/bootstrap/latest.log"
}
