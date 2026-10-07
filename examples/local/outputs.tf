output "server_user_data" {
  description = "cloud-init for the init candidate and the other servers."
  value       = module.bootstrap.server_user_data
}

output "agent_user_data" {
  description = "cloud-init per agent pool."
  value       = module.bootstrap.agent_user_data
}

output "server_secret_paths" {
  description = "Secret name to path for servers."
  value       = module.bootstrap.server_secret_paths
}

output "agent_secret_paths" {
  description = "Secret name to path for agents."
  value       = module.bootstrap.agent_secret_paths
}

output "server_secret_contents" {
  description = "Secret name to content, seeded onto the VMs by run.sh."
  value       = module.bootstrap.server_secret_contents
  sensitive   = true
}

output "kubeconfig" {
  description = "Admin kubeconfig against the registration address."
  value       = module.bootstrap.kubeconfig
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 PEM of the server CA."
  value       = base64encode(module.bootstrap.server_ca_certificate)
}

output "admin_client_certificate" {
  description = "Base64 PEM of the admin client certificate."
  value       = base64encode(module.bootstrap.admin_client_certificate)
}

output "admin_client_key" {
  description = "Base64 PEM of the admin client key."
  value       = base64encode(module.bootstrap.admin_client_key)
  sensitive   = true
}

output "cni_node_size" {
  description = "Nodes cni-bootstrap waits for, as the Azure module computes it."
  value       = var.cni == "kube-ovn" ? 1 : 3
}

output "cni_node_selector" {
  description = "Selector of those nodes, as the Azure module computes it."
  value       = var.cni == "kube-ovn" ? "kube-ovn/role=master" : "node-role.kubernetes.io/control-plane=true"
}
