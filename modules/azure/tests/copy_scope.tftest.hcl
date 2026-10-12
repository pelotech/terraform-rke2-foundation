# Storage copy scope: every account restricts copies to the tenant by default, and an explicit scope reaches its account.
mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "invalid_copy_scope_is_rejected" {
  command = plan
  variables {
    etcd_backup       = { storage_account_name = "stplatformdevetcd", allowed_copy_scope = "Tenant" }
    blob_csi          = { storage_account_name = "stplatformdevcsi", allowed_copy_scope = "Tenant" }
    workload_identity = { storage_account_name = "stplatformdevoidc", allowed_copy_scope = "Tenant" }
  }
  expect_failures = [var.etcd_backup, var.blob_csi, var.workload_identity]
}

run "copies_default_to_the_same_tenant" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi" }
  }
  assert {
    condition     = azurerm_storage_account.etcd_backup[0].allowed_copy_scope == "AAD" && azurerm_storage_account.blob_csi[0].allowed_copy_scope == "AAD" && azurerm_storage_account.oidc[0].allowed_copy_scope == "AAD"
    error_message = "Every storage account restricts copies to the same Entra tenant unless told otherwise."
  }
}

run "explicit_scope_reaches_each_account" {
  command = plan
  variables {
    etcd_backup = {
      storage_account_name = "stplatformdevetcd"
      allowed_copy_scope   = "PrivateLink"
      network_access       = "PrivateEndpoint"
      private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.usgovcloudapi.net"]
    }
    blob_csi = {
      storage_account_name = "stplatformdevcsi"
      allowed_copy_scope   = "PrivateLink"
      network_access       = "PrivateEndpoint"
      private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.usgovcloudapi.net"]
    }
    workload_identity = { storage_account_name = "stplatformdevoidc", allowed_copy_scope = "All" }
  }
  assert {
    condition     = azurerm_storage_account.etcd_backup[0].allowed_copy_scope == "PrivateLink" && azurerm_storage_account.blob_csi[0].allowed_copy_scope == "PrivateLink" && azurerm_storage_account.oidc[0].allowed_copy_scope == "All"
    error_message = "Each storage account carries the copy scope it was given."
  }
}
