locals {
  etcd_backup_enabled       = var.etcd_backup.enabled
  etcd_backup_container_url = local.etcd_backup_enabled ? "${azurerm_storage_account.etcd_backup[0].primary_blob_endpoint}${azurerm_storage_container.etcd_backup[0].name}" : null
}

# A private account of its own: the OIDC account is public by design and the blob CSI account belongs to workloads.
resource "azurerm_storage_account" "etcd_backup" {
  count                           = local.etcd_backup_enabled ? 1 : 0
  name                            = coalesce(var.etcd_backup.storage_account_name, substr("${local.storage_account_name_stem}etcd", 0, 24))
  resource_group_name             = local.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = var.etcd_backup.replication_type
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.etcd_backup.retention_days
    }
    container_delete_retention_policy {
      days = var.etcd_backup.retention_days
    }
  }
}

resource "azurerm_storage_account_network_rules" "etcd_backup" {
  count                      = local.etcd_backup_enabled ? 1 : 0
  storage_account_id         = azurerm_storage_account.etcd_backup[0].id
  default_action             = "Deny"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = [local.node_subnet_id]
}

resource "azurerm_storage_container" "etcd_backup" {
  count                 = local.etcd_backup_enabled ? 1 : 0
  name                  = "etcd-snapshots"
  storage_account_id    = azurerm_storage_account.etcd_backup[0].id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "etcd_backup" {
  count              = local.etcd_backup_enabled ? 1 : 0
  storage_account_id = azurerm_storage_account.etcd_backup[0].id

  rule {
    name    = "expire-snapshots"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${azurerm_storage_container.etcd_backup[0].name}/"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.etcd_backup.retention_days
      }
      version {
        delete_after_days_since_creation = var.etcd_backup.retention_days
      }
    }
  }
}
