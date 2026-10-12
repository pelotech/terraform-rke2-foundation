# Azure policy overrides must reach the planned resources without changing existing defaults.
mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "invalid_copy_scope_is_rejected" {
  command = plan
  variables {
    etcd_backup = { storage_account_name = "stplatformdevetcd", allowed_copy_scope = "Tenant" }
    blob_csi    = { storage_account_name = "stplatformdevcsi", allowed_copy_scope = "Tenant" }
  }
  expect_failures = [var.etcd_backup, var.blob_csi]
}

run "invalid_load_balancer_name_is_rejected" {
  command = plan
  variables {
    cluster_endpoint = { public = false, internal_lb_name = "" }
  }
  expect_failures = [var.cluster_endpoint]
}

run "existing_names_and_copy_scope_are_preserved" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi" }
  }
  assert {
    condition     = azurerm_lb.api.name == "lb-platformdev-api" && azurerm_lb.api_public[0].name == "lb-platformdev-api-public"
    error_message = "Omitting the internal LB name must preserve both existing load balancer names."
  }
  assert {
    condition     = azurerm_storage_account.etcd_backup[0].allowed_copy_scope == null && azurerm_storage_account.blob_csi[0].allowed_copy_scope == null
    error_message = "Omitting copy scope must preserve the existing provider default on both storage accounts."
  }
}

run "private_cluster_honors_customer_resource_policies" {
  command = plan
  variables {
    cluster_endpoint = { public = false, internal_lb_name = "lbi-platformdev-api" }
    etcd_backup = {
      storage_account_name = "stplatformdevetcd"
      allowed_copy_scope   = "AAD"
      network_access       = "PrivateEndpoint"
      private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.usgovcloudapi.net"]
    }
    blob_csi = {
      storage_account_name = "stplatformdevcsi"
      allowed_copy_scope   = "AAD"
      network_access       = "PrivateEndpoint"
      private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.usgovcloudapi.net"]
    }
  }
  assert {
    condition     = azurerm_lb.api.name == "lbi-platformdev-api" && length(azurerm_lb.api_public) == 0
    error_message = "The private API load balancer must use the supplied policy-compliant name."
  }
  assert {
    condition     = azurerm_storage_account.etcd_backup[0].name == "stplatformdevetcd" && azurerm_storage_account.etcd_backup[0].allowed_copy_scope == "AAD" && azurerm_storage_account.blob_csi[0].name == "stplatformdevcsi" && azurerm_storage_account.blob_csi[0].allowed_copy_scope == "AAD"
    error_message = "Both storage accounts must retain their supplied names and restrict copies to the same tenant."
  }
  assert {
    condition     = azurerm_storage_account.etcd_backup[0].public_network_access == "Disabled" && azurerm_storage_account.blob_csi[0].public_network_access == "Disabled"
    error_message = "Copy restrictions must preserve private networking on both accounts."
  }
}
