# Blob storage for the blob CSI driver the GitOps layer installs.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "null_creates_nothing" {
  command = plan
  assert {
    condition     = length(azurerm_storage_account.blob_csi) == 0 && length(azurerm_storage_container.blob_csi) == 0 && !contains(keys(azurerm_role_assignment.agent), "blob_csi")
    error_message = "no storage account, containers or grant with blob_csi null"
  }
  assert {
    condition     = output.blob_csi_storage_account_id == null && output.blob_csi_storage_account_name == null && length(output.blob_csi_container_names) == 0
    error_message = "null outputs without blob CSI"
  }
}

run "set_creates_account_containers_and_grant" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi", containers = ["backups", "media"] }
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].name == "acmeplatformdevcsi" && azurerm_storage_account.blob_csi[0].shared_access_key_enabled == false && azurerm_storage_account.blob_csi[0].min_tls_version == "TLS1_2" && azurerm_storage_account.blob_csi[0].allowed_copy_scope == "AAD"
    error_message = "the account carries the given name; keys off; TLS 1.2"
  }
  assert {
    condition     = azurerm_storage_account_network_rules.blob_csi[0].default_action == "Deny" && length(azurerm_storage_account_network_rules.blob_csi[0].virtual_network_subnet_ids) == 1
    error_message = "NodeSubnet access denies everything but the node subnet"
  }
  assert {
    condition     = [for e in azurerm_subnet.nodes[0].service_endpoint : e.service] == ["Microsoft.Storage"]
    error_message = "NodeSubnet access needs the storage service endpoint on the node subnet"
  }
  assert {
    condition     = sort(keys(azurerm_storage_container.blob_csi)) == tolist(["backups", "media"]) && azurerm_storage_container.blob_csi["backups"].container_access_type == "private"
    error_message = "one private container per name"
  }
  assert {
    condition     = azurerm_role_assignment.agent["blob_csi"].role_definition_name == "Storage Blob Data Contributor"
    error_message = "the agent identity mounts the containers, so it gets Storage Blob Data Contributor"
  }
}

run "public_access_opens_the_account" {
  command = plan
  variables {
    etcd_backup = null
    blob_csi    = { storage_account_name = "acmeplatformdevcsi", network_access = "Public", shared_access_key_enabled = true }
  }
  assert {
    condition     = azurerm_storage_account_network_rules.blob_csi[0].default_action == "Allow" && length(azurerm_storage_account_network_rules.blob_csi[0].virtual_network_subnet_ids) == 0 && azurerm_storage_account.blob_csi[0].shared_access_key_enabled == true
    error_message = "Public allows every network; keys follow the input"
  }
  assert {
    condition     = length(azurerm_subnet.nodes[0].service_endpoint) == 0
    error_message = "no storage service endpoint when the account is public"
  }
}

run "private_endpoint_preserves_keys_and_private_containers" {
  command = plan
  variables {
    etcd_backup = null
    blob_csi = {
      storage_account_name      = "acmeplatformdevcsi"
      containers                = ["backups"]
      network_access            = "PrivateEndpoint"
      private_dns_zone_ids      = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.usgovcloudapi.net"]
      shared_access_key_enabled = true
    }
  }
  assert {
    condition     = !azurerm_storage_account.blob_csi[0].public_network_access_enabled && azurerm_storage_account.blob_csi[0].shared_access_key_enabled && !azurerm_storage_account.blob_csi[0].allow_nested_items_to_be_public && azurerm_storage_container.blob_csi["backups"].container_access_type == "private"
    error_message = "Private networking preserves the configured authentication and forbids anonymous container access."
  }
  assert {
    condition     = azurerm_storage_account_network_rules.blob_csi[0].default_action == "Deny" && length(azurerm_storage_account_network_rules.blob_csi[0].virtual_network_subnet_ids) == 0 && length(azurerm_subnet.nodes[0].service_endpoint) == 0
    error_message = "PrivateEndpoint must not enable or require Microsoft.Storage service endpoints."
  }
  assert {
    condition     = length(azurerm_private_endpoint.storage) == 1 && azurerm_private_endpoint.storage["blob-csi"].name == "pep-platformdev-blob-csi" && azurerm_private_endpoint.storage["blob-csi"].private_dns_zone_group[0].private_dns_zone_ids == var.blob_csi.private_dns_zone_ids
    error_message = "One Blob endpoint integrates with the supplied DNS zone."
  }
}

run "private_endpoint_requires_dns_zone" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi", network_access = "PrivateEndpoint" }
  }
  expect_failures = [var.blob_csi]
}
