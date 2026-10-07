# Inputs for the helm provider and the cni-bootstrap module.
output "cloud" {
  description = "Cloud this stack runs on. Pass it to cni-bootstrap cloud."
  value       = "azure"
}

output "distribution" {
  description = "Kubernetes distribution this stack runs. Pass it to cni-bootstrap distribution."
  value       = "rke2"
}

output "kube_exec" {
  description = "kubelogin exec block for the helm provider and cni-bootstrap, null unless entra_oidc is on. Without it, use admin_client_certificate and admin_client_key."
  value       = local.kube_exec
}

output "cluster_name" {
  description = "Name of the cluster."
  value       = var.name
}

output "cluster_version" {
  description = "RKE2 release the nodes install."
  value       = var.rke2_version
}

output "cluster_endpoint" {
  description = "API server URL for the helm provider and cni-bootstrap: the public FQDN, or the internal address for a private cluster."
  value       = local.cluster_endpoint

  # Consumers poll the nodes through this value, so it waits for the nodes: the endpoint exists minutes before them.
  depends_on = [azurerm_linux_virtual_machine.server, azurerm_linux_virtual_machine_scale_set.agent]
}


output "cluster_ca_certificate" {
  description = "Base64 encoded PEM of the CA that signs the API server certificate, known at plan time."
  value       = base64encode(module.bootstrap.server_ca_certificate)
}

output "cluster_api_host" {
  description = "Host for Cilium k8sServiceHost. Every RKE2 node runs a local API load balancer on 127.0.0.1:6443, so this is not the external host."
  value       = "127.0.0.1"
}

output "cluster_api_port" {
  description = "Port for Cilium k8sServicePort, the RKE2 agent load balancer port."
  value       = local.api_ports.api
}

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR. Pass it to cni-bootstrap service_cidr."
  value       = var.service_cidr
}

output "cluster_pod_cidr" {
  description = "Pod CIDR, the RKE2 cluster-cidr. Pass it to cni-bootstrap pod_cidr."
  value       = var.pod_cidr
}

output "cni_node_size" {
  description = "Nodes cni-bootstrap waits for: the CNI pool size for kube-ovn, otherwise the server count, so Helm connects once the API is up. Pass it to cni-bootstrap wait_for_nodes_count."
  value       = local.cni_node_size
}

output "cni_node_selector" {
  description = "Label selector of those nodes. Pass it to cni-bootstrap wait_for_nodes_selector."
  value       = local.cni_node_selector
}

output "selinux_container_dirs_resolved" {
  description = "Host directories the bootstrap labels container_file_t on a host with SELinux on, from the CNI profile; introspection for tests."
  value       = local.cni_profile.selinux_container_dirs
}

# Credentials. The certificate is public; the key and the kubeconfig are secret.
output "admin_client_certificate" {
  description = "Base64 encoded PEM admin client certificate, system:admin in system:masters, for the helm provider's client_certificate."
  value       = base64encode(module.bootstrap.admin_client_certificate)
}

output "admin_client_key" {
  description = "Base64 encoded PEM private key of the admin client certificate, for the helm provider's client_key."
  value       = base64encode(module.bootstrap.admin_client_key)
  sensitive   = true
}

output "kubeconfig" {
  description = "Admin kubeconfig for cluster_endpoint with the client certificate, the break-glass path. With entra_oidc on, people and pipelines use kubeconfig_entra."
  value       = module.bootstrap.kubeconfig
  sensitive   = true
}

output "kubeconfig_entra" {
  description = "Kubeconfig for cluster_endpoint with the kubelogin exec block, null unless entra_oidc is on. It holds no secret: kubelogin fetches the token."
  value       = local.kubeconfig_entra
}

# Subscription and tenant, for charts that need them next to the identities.
output "subscription_id" {
  description = "Azure subscription the stack runs in."
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Entra tenant of the subscription."
  value       = data.azurerm_client_config.current.tenant_id
}

# Resource groups, network and API addresses.
output "resource_group_name" {
  description = "Resource group holding the network, Key Vault, identities and load balancers."
  value       = local.resource_group_name
}

output "node_resource_group_name" {
  description = "Resource group holding the nodes and what the cloud provider and CSI driver create."
  value       = azurerm_resource_group.nodes.name
}

output "location" {
  description = "Azure region of the stack."
  value       = var.location
}

output "region" {
  description = "Same value as location, for consumers that expect an output named region."
  value       = var.location
}

output "vnet_id" {
  description = "ID of the VNet, created or taken from existing_vnet."
  value       = local.create_vnet ? azurerm_virtual_network.this[0].id : var.existing_vnet.vnet_id
}

output "node_subnet_id" {
  description = "ID of the subnet every node and private endpoint uses."
  value       = local.node_subnet_id
}

output "database_subnet_id" {
  description = "ID of the database subnet, null unless vnet.database_subnet_cidr is set."
  value       = one(azurerm_subnet.database[*].id)
}

output "nat_gateway_public_ips" {
  description = "Public IP addresses of the NAT Gateway, for allow lists. Empty with existing_vnet."
  value       = azurerm_public_ip.nat[*].ip_address
}

output "api_private_ip" {
  description = "Internal address of the API server and the registration address every node joins through."
  value       = local.api_private_ip_resolved
}

output "api_public_ip" {
  description = "Public address of the API server, null for a private cluster."
  value       = one(azurerm_public_ip.api[*].ip_address)
}

output "api_public_fqdn" {
  description = "Public FQDN of the API server, null for a private cluster."
  value       = one(azurerm_public_ip.api[*].fqdn)
}

output "node_security_group_id" {
  description = "ID of the network security group on every node, where cloud-provider-azure adds Service rules."
  value       = azurerm_network_security_group.nodes.id
}

# Key Vault and identities.
output "key_vault_id" {
  description = "ID of the Key Vault holding the tokens, the CA set and the generated SSH key."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Name of that Key Vault."
  value       = azurerm_key_vault.this.name
}

output "server_identity_client_id" {
  description = "Client ID of the server identity, which cloud-provider-azure and cluster-autoscaler use."
  value       = azurerm_user_assigned_identity.server.client_id
}

output "server_identity_principal_id" {
  description = "Principal ID of the server identity, for extra role assignments."
  value       = azurerm_user_assigned_identity.server.principal_id
}

output "server_identity_id" {
  description = "Resource ID of the server identity."
  value       = azurerm_user_assigned_identity.server.id
}

output "agent_identity_client_id" {
  description = "Client ID of the agent identity, the kubelet identity the CSI drivers use."
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "agent_identity_principal_id" {
  description = "Principal ID of the agent identity, for extra role assignments."
  value       = azurerm_user_assigned_identity.agent.principal_id
}

output "agent_identity_id" {
  description = "Resource ID of the agent identity."
  value       = azurerm_user_assigned_identity.agent.id
}

# Nodes.
output "server_vm_ids" {
  description = "Resource IDs of the server VMs, in index order."
  value       = azurerm_linux_virtual_machine.server[*].id
}

output "agent_scale_set_ids" {
  description = "Resource ID of each agent scale set, by pool name."
  value       = { for pool, vmss in azurerm_linux_virtual_machine_scale_set.agent : pool => vmss.id }
}

# Resolved configuration.
output "cni_node_pool_enabled" {
  description = "Whether the CNI node pool is created."
  value       = local.cni_node_pool_enabled
}

output "cni_node_taints_resolved" {
  description = "Taints of the CNI node pool as key, value and effect objects. Set even when the pool is not created."
  value       = local.cni_node_pool_taints
}

output "cni_node_labels_resolved" {
  description = "Labels of the CNI node pool. Set even when the pool is not created."
  value       = local.cni_node_pool_labels
}

output "dns_service_ip_resolved" {
  description = "Cluster DNS service IP after resolving dns_service_ip and service_cidr."
  value       = local.dns_service_ip
}

output "agent_pools_resolved" {
  description = "Agent pools after adding the CNI pool, with taints as the key=value:Effect strings RKE2 receives."
  value       = local.agent_pools_resolved
}

output "server_config_resolved" {
  description = "RKE2 server config.yaml as a map, without the join drop-ins."
  value       = module.bootstrap.server_config
}

output "cloud_config_resolved" {
  description = "cloud-provider-azure cloud config the servers write into the azure-cloud-config secret."
  value       = local.cloud_config
}

output "server_manifests_resolved" {
  description = "Manifests every server writes to the RKE2 manifests directory, file name to YAML."
  value       = local.server_manifests
}

# Workload identity. The GitOps layer sets each client_id on the azure.workload.identity/client-id annotation.
output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, null when workload identity is off. Use it for federated identity credentials you create yourself."
  value       = local.oidc_issuer_url
}

output "external_dns_client_id" {
  description = "Client ID of the external-dns workload identity, null when disabled."
  value       = try(azurerm_user_assigned_identity.workload["external_dns"].client_id, null)
}

output "external_dns_principal_id" {
  description = "Principal ID of the external-dns workload identity, for role assignments you create yourself."
  value       = try(azurerm_user_assigned_identity.workload["external_dns"].principal_id, null)
}

output "external_dns_identity_id" {
  description = "Resource ID of the external-dns workload identity, null when disabled."
  value       = try(azurerm_user_assigned_identity.workload["external_dns"].id, null)
}

output "cert_manager_client_id" {
  description = "Client ID of the cert-manager workload identity, null when disabled."
  value       = try(azurerm_user_assigned_identity.workload["cert_manager"].client_id, null)
}

output "cert_manager_principal_id" {
  description = "Principal ID of the cert-manager workload identity, for role assignments you create yourself."
  value       = try(azurerm_user_assigned_identity.workload["cert_manager"].principal_id, null)
}

output "cert_manager_identity_id" {
  description = "Resource ID of the cert-manager workload identity, null when disabled."
  value       = try(azurerm_user_assigned_identity.workload["cert_manager"].id, null)
}

output "workload_identity_enabled_resolved" {
  description = "Which workload identities are created, after enabled and overrides."
  value       = local.workload_identity_enabled
}

output "workload_identity_service_accounts_resolved" {
  description = "Namespace and service account each created identity federates with."
  value       = local.enabled_workload_identities
}

# Blob CSI.
output "blob_csi_storage_account_id" {
  description = "Resource ID of the blob CSI storage account, null when not created."
  value       = one(azurerm_storage_account.blob_csi[*].id)
}

output "blob_csi_storage_account_name" {
  description = "Name of the blob CSI storage account, null when not created. Use it as the storageAccount of a PersistentVolume."
  value       = one(azurerm_storage_account.blob_csi[*].name)
}

output "blob_csi_container_names" {
  description = "Names of the blob containers created in the blob CSI storage account, empty when none."
  value       = sort(keys(azurerm_storage_container.blob_csi))
}

# etcd backups.
output "etcd_backup_storage_account_id" {
  description = "Resource ID of the etcd snapshot storage account, null when etcd_backup is disabled. The scope for a private endpoint or extra grants."
  value       = one(azurerm_storage_account.etcd_backup[*].id)
}

output "etcd_backup_container_url" {
  description = "URL of the etcd-snapshots container; snapshots sit under <name>/<server>/<file>. Null when etcd_backup is disabled."
  value       = local.etcd_backup_container_url
}
