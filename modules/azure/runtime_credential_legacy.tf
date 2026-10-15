# Legacy path: the nodes run with a service principal instead of the managed identities in identities.tf, for
# subscriptions where the applying principal cannot create identities or role assignments. Recommended: leave
# runtime_credential null. To drop this path, delete this file and the managed_identities branches it breaks.

variable "runtime_credential" {
  type = object({
    client_id     = string
    client_secret = string
  })
  default     = null
  sensitive   = true
  description = "Service principal the nodes use instead of managed identities: cloud-provider-azure, the CSI drivers and the snapshot upload authenticate with it, and cloud-init carries the join tokens and CA set instead of the Key Vault. null keeps the default: one managed identity per role with the module's role assignments and the vault. Set it where the applying principal cannot create identities or role assignments; the Key Vault then stays but holds no secrets."
}

locals {
  # nonsensitive: the comparison inherits the credential's mark, and counts cannot depend on a sensitive value.
  managed_identities = nonsensitive(var.runtime_credential == null)
  legacy_client_id   = local.managed_identities ? null : nonsensitive(var.runtime_credential.client_id)

  # access_token RESOURCE comes from Entra with the client credentials.
  legacy_token_script = local.managed_identities ? "" : templatefile("${path.module}/templates/client-credentials-token.sh.tftpl", {
    login_host    = local.azure_cloud.entra_login_host
    tenant_id     = data.azurerm_client_config.current.tenant_id
    client_secret = var.runtime_credential.client_secret
  })

  # The secrets travel in cloud-init, so each role's fetch script carries its own.
  legacy_fetch_secrets_scripts = local.managed_identities ? {} : {
    for role, paths in { server = module.bootstrap.server_secret_paths, agent = module.bootstrap.agent_secret_paths } :
    role => templatefile("${path.module}/templates/embedded-secrets.sh.tftpl", {
      secrets = { for name in keys(paths) : name => module.bootstrap.server_secret_contents[name] }
    })
  }

  legacy_cloud_config_public = local.managed_identities ? {} : { aadClientId = local.legacy_client_id }
  legacy_cloud_config_secret = local.managed_identities ? {} : { aadClientSecret = var.runtime_credential.client_secret }
}
