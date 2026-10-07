locals {
  server_taints = var.servers.schedulable ? [] : ["CriticalAddonsOnly=true:NoSchedule"]

  workload_identity_apiserver_args = local.oidc_issuer_enabled ? [
    "service-account-issuer=${local.oidc_issuer_url}",
    "service-account-jwks-uri=${local.oidc_issuer_url}openid/v1/jwks",
  ] : []

  imds_token_script = file("${path.module}/templates/imds-token.sh")
  blob_put_script   = file("${path.module}/templates/blob-put.sh")

  # Each role fetches with its own identity; bootstrap.sh decides which secrets.
  fetch_secrets_scripts = {
    for role, identity in { server = azurerm_user_assigned_identity.server, agent = azurerm_user_assigned_identity.agent } :
    role => templatefile("${path.module}/templates/fetch-secrets.sh.tftpl", {
      vault_uri  = azurerm_key_vault.this.vault_uri
      audience   = local.azure_cloud.key_vault_audience
      client_id  = identity.client_id
      imds_token = local.imds_token_script
    })
  }

  put_snapshot_script = local.etcd_backup_enabled ? templatefile("${path.module}/templates/put-snapshot.sh.tftpl", {
    client_id     = azurerm_user_assigned_identity.server.client_id
    container_url = local.etcd_backup_container_url
    imds_token    = local.imds_token_script
    blob_put      = local.blob_put_script
  }) : ""

  post_bootstrap_script = local.oidc_issuer_enabled ? templatefile("${path.module}/templates/post-bootstrap.sh.tftpl", {
    client_id     = azurerm_user_assigned_identity.server.client_id
    issuer_url    = local.oidc_issuer_url
    blob_endpoint = azurerm_storage_account.oidc[0].primary_blob_endpoint
    imds_token    = local.imds_token_script
    blob_put      = local.blob_put_script
  }) : ""
}

module "bootstrap" {
  source = "../bootstrap"

  name                   = var.name
  rke2_version           = var.rke2_version
  registration_address   = local.api_private_ip_resolved
  api_server_url         = local.cluster_endpoint
  tls_sans               = azurerm_public_ip.api[*].fqdn
  service_cidr           = var.service_cidr
  pod_cidr               = var.pod_cidr
  cluster_dns            = local.dns_service_ip
  cni                    = local.cni_profile.rke2_cni
  disable_kube_proxy     = local.cni_profile.disable_kube_proxy
  cloud_provider_name    = "external"
  cis_profile            = var.cis_profile
  secrets_encryption     = var.secrets_encryption
  disable_components     = var.disable_components
  ingress_controller     = var.ingress_controller
  certificate_renewal    = var.certificate_renewal
  disable_firewalld      = var.disable_firewalld
  selinux_container_dirs = local.cni_profile.selinux_container_dirs
  etcd_disk_device       = var.servers.etcd_disk.enabled ? "/dev/disk/azure/scsi1/lun${local.etcd_disk_lun}" : null
  put_snapshot_script    = local.put_snapshot_script
  server_labels          = var.servers.labels
  server_taints          = local.server_taints
  bootstrap_wait_seconds = var.servers.bootstrap_wait_seconds
  pki                    = var.pki

  kube_apiserver_args          = concat(local.workload_identity_apiserver_args, local.entra_oidc_apiserver_args, var.kube_apiserver_args)
  kube_controller_manager_args = concat(["configure-cloud-routes=false"], var.kube_controller_manager_args)
  kubelet_args                 = var.kubelet_args
  extra_server_config          = var.extra_server_config
  extra_agent_config           = var.extra_agent_config

  agent_pools           = local.agent_pools_resolved
  server_manifests      = local.server_manifests
  fetch_secrets_scripts = local.fetch_secrets_scripts
  post_bootstrap_script = local.post_bootstrap_script
}
