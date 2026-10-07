output "resolved_set" {
  description = "Helm --set values cni-bootstrap installed."
  value       = module.cni.resolved_set
}
