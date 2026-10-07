# Secrets for the cloud module to store. The path maps are static, so a cloud module can for_each over them.
output "server_secret_paths" {
  description = "Secret name to the path under SECRET_DIR a server's fetch script must write it to."
  value       = local.server_secret_paths
}

output "agent_secret_paths" {
  description = "Secret name to the path under SECRET_DIR an agent's fetch script must write it to."
  value       = local.agent_secret_paths
}

output "server_secret_contents" {
  description = "Secret name to content, every secret in server_secret_paths, for the cloud module to store."
  value       = local.secret_contents
  sensitive   = true
}

# Credentials and public material.
output "server_ca_certificate" {
  description = "PEM of the CA that signs the API server certificate. Clients verify the API with it."
  value       = tls_self_signed_cert.ca["server_ca"].cert_pem
}

output "client_ca_certificate" {
  description = "PEM of the CA that signs client certificates, the admin credential among them."
  value       = tls_self_signed_cert.ca["client_ca"].cert_pem
}

output "service_account_public_key" {
  description = "PEM public key matching the service account signing key, for a JWKS built outside the cluster."
  value       = tls_private_key.service_account.public_key_pem
}

output "admin_client_certificate" {
  description = "PEM admin client certificate, system:admin in system:masters, signed by the client CA."
  value       = tls_locally_signed_cert.admin.cert_pem
}

output "admin_client_key" {
  description = "PEM private key of the admin client certificate."
  value       = tls_private_key.admin.private_key_pem
  sensitive   = true
}

output "kubeconfig" {
  description = "Admin kubeconfig: api_server_url, the server CA and the admin client certificate."
  value       = local.kubeconfig
  sensitive   = true
}

# Rendered configuration, for inspection and tests.
output "server_config" {
  description = "RKE2 server config.yaml as a map, without the join drop-ins."
  value       = local.server_config
}

output "agent_config" {
  description = "RKE2 agent config.yaml as a map per pool, without the join drop-ins."
  value       = local.agent_config
}

output "server_user_data" {
  description = "cloud-init for servers: init_candidate for server zero, member for the others."
  value       = { init_candidate = local.user_data["init_candidate"], member = local.user_data["member"] }
}

output "agent_user_data" {
  description = "cloud-init per agent pool."
  value       = { for pool in keys(var.agent_pools) : pool => local.user_data["agent_${pool}"] }
}
