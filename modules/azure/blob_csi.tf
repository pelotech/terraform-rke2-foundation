locals {
  create_blob_storage_account = var.blob_csi.enabled && var.blob_csi.create_storage_account
  blob_csi_node_subnet_only   = local.create_blob_storage_account && var.blob_csi.network_access == "NodeSubnet"
}

resource "azurerm_storage_account" "blob_csi" {
  count                           = local.create_blob_storage_account ? 1 : 0
  name                            = coalesce(var.blob_csi.storage_account_name, substr("${local.storage_account_name_stem}csi", 0, 24))
  resource_group_name             = local.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.blob_csi.shared_access_key_enabled
  tags                            = var.tags
}

# A separate resource, because the inline block cannot hold an open account: the provider reads Allow without rules as no block.
resource "azurerm_storage_account_network_rules" "blob_csi" {
  count                      = local.create_blob_storage_account ? 1 : 0
  storage_account_id         = azurerm_storage_account.blob_csi[0].id
  default_action             = local.blob_csi_node_subnet_only ? "Deny" : "Allow"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = local.blob_csi_node_subnet_only ? concat([local.node_subnet_id], var.blob_csi.extra_subnet_ids) : []
}

resource "azurerm_storage_container" "blob_csi" {
  for_each              = local.create_blob_storage_account ? toset(var.blob_csi.containers) : toset([])
  name                  = each.value
  storage_account_id    = azurerm_storage_account.blob_csi[0].id
  container_access_type = "private"
}
