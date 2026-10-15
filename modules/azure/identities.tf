locals {
  # Servers run cloud-provider-azure and cluster-autoscaler with their identity; agents run the disk and blob CSI drivers with theirs.
  server_identity_grants = merge(
    {
      node_resource_group = { scope = local.node_resource_group_id, role = "Contributor" }
      node_subnet         = { scope = local.node_subnet_id, role = "Network Contributor" }
      key_vault_secrets   = { scope = azurerm_key_vault.this.id, role = "Key Vault Secrets User" }
    },
    # The module's own group sits in the node group, which Contributor already covers.
    local.create_vnet ? {} : {
      node_security_group = { scope = var.network.existing.security_group_id, role = "Network Contributor" }
    },
    local.oidc_issuer_enabled ? {
      oidc_storage = { scope = azurerm_storage_account.oidc[0].id, role = "Storage Blob Data Contributor" }
    } : {},
    local.etcd_backup_enabled ? {
      etcd_backup = { scope = azurerm_storage_container.etcd_backup[0].id, role = "Storage Blob Data Contributor" }
    } : {},
  )
  agent_identity_grants = merge(
    { node_resource_group = { scope = local.node_resource_group_id, role = "Contributor" } },
    # Agents read only their own secrets, each granted on the secret itself.
    { for name in keys(module.bootstrap.agent_secret_paths) : name => { scope = azurerm_key_vault_secret.node[name].resource_versionless_id, role = "Key Vault Secrets User" } if local.managed_identities },
    local.create_blob_storage_account ? {
      blob_csi = { scope = azurerm_storage_account.blob_csi[0].id, role = "Storage Blob Data Contributor" }
    } : {},
  )
}

resource "azurerm_user_assigned_identity" "server" {
  count               = local.managed_identities ? 1 : 0
  name                = "id-${var.name}-server"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "agent" {
  count               = local.managed_identities ? 1 : 0
  name                = "id-${var.name}-agent"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "server" {
  for_each                         = local.managed_identities ? local.server_identity_grants : {}
  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.server[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "agent" {
  for_each                         = local.managed_identities ? local.agent_identity_grants : {}
  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.agent[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

moved {
  from = azurerm_user_assigned_identity.server
  to   = azurerm_user_assigned_identity.server[0]
}

moved {
  from = azurerm_user_assigned_identity.agent
  to   = azurerm_user_assigned_identity.agent[0]
}
