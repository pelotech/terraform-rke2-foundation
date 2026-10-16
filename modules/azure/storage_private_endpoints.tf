locals {
  storage_private_endpoints = merge(
    local.etcd_backup_private_endpoint ? {
      etcd-backup = {
        resource_id          = azurerm_storage_account.etcd_backup[0].id
        private_dns_zone_ids = var.etcd_backup.private_dns_zone_ids
      }
    } : {},
    local.blob_csi_private_endpoint ? {
      blob-csi = {
        resource_id          = azurerm_storage_account.blob_csi[0].id
        private_dns_zone_ids = var.blob_csi.private_dns_zone_ids
      }
    } : {},
  )
}

# Reuse the customer's subnet and DNS zones; this module owns only the endpoints.
resource "azurerm_private_endpoint" "storage" {
  for_each            = local.storage_private_endpoints
  name                = "pep-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = local.resource_group_name
  subnet_id           = local.node_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # No zone ids: the zone's owner creates the record, so the applying identity needs no join on the zone.
  dynamic "private_dns_zone_group" {
    for_each = length(each.value.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = each.value.private_dns_zone_ids
    }
  }
}
