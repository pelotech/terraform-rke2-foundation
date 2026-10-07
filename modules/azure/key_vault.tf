locals {
  key_vault_name = coalesce(var.key_vault.name, trimsuffix(substr("kv-${var.name}", 0, 24), "-"))
  create_ssh_key = var.ssh_public_key == null
  ssh_public_key = local.create_ssh_key ? tls_private_key.ssh[0].public_key_openssh : var.ssh_public_key
}

resource "azurerm_key_vault" "this" {
  name                          = local.key_vault_name
  location                      = var.location
  resource_group_name           = local.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = var.key_vault.network_access == "Public"
  tags                          = var.tags
}

resource "azurerm_role_assignment" "key_vault_admin" {
  for_each             = toset(var.key_vault.admin_object_ids)
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

resource "tls_private_key" "ssh" {
  count     = local.create_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Writing secrets under RBAC needs Secrets Officer, so the applying principal must be in key_vault.admin_object_ids.
resource "azurerm_key_vault_secret" "node" {
  for_each     = module.bootstrap.server_secret_paths
  name         = each.key
  value        = module.bootstrap.server_secret_contents[each.key]
  content_type = "text/plain"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.key_vault_admin]
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  count        = local.create_ssh_key ? 1 : 0
  name         = "ssh-private-key"
  value        = tls_private_key.ssh[0].private_key_openssh
  content_type = "text/plain"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.key_vault_admin]
}
