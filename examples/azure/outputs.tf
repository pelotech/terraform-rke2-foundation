output "kubeconfig" {
  description = "Admin kubeconfig. Write it to a file and point KUBECONFIG at it for smoke-test.sh."
  value       = module.stack.kubeconfig
  sensitive   = true
}

output "cluster_endpoint" {
  description = "API server URL."
  value       = module.stack.cluster_endpoint
}

output "api_public_fqdn" {
  description = "Public FQDN of the API server."
  value       = module.stack.api_public_fqdn
}

output "resource_group_name" {
  description = "Resource group of the network, vault and identities."
  value       = module.stack.resource_group_name
}

output "node_resource_group_name" {
  description = "Resource group of the nodes, where the cloud provider creates load balancers and disks."
  value       = module.stack.node_resource_group_name
}

output "key_vault_name" {
  description = "Key Vault holding the join tokens and the CA set."
  value       = module.stack.key_vault_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer the servers publish for workload identity."
  value       = module.stack.oidc_issuer_url
}

output "server_identity_client_id" {
  description = "Client id of the server identity, which cloud-provider-azure and the CSI controller use."
  value       = module.stack.server_identity_client_id
}
