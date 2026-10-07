# Blob storage for the blob CSI driver the GitOps layer installs.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "off_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_storage_account.blob_csi) == 0 && length(azurerm_storage_container.blob_csi) == 0 && !contains(keys(azurerm_role_assignment.agent), "blob_csi")
    error_message = "no storage account, containers or grant unless blob_csi.enabled"
  }
}

run "enabled_creates_account_containers_and_grant" {
  command = plan
  variables {
    blob_csi = { enabled = true, containers = ["backups", "media"] }
  }
  assert {
    condition     = azurerm_storage_account.blob_csi[0].name == "acmeplatformdevcsi" && azurerm_storage_account.blob_csi[0].shared_access_key_enabled == false && azurerm_storage_account.blob_csi[0].min_tls_version == "TLS1_2"
    error_message = "the account name comes from the Owner tag and the cluster name; keys off; TLS 1.2"
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
    etcd_backup = { enabled = false }
    blob_csi    = { enabled = true, network_access = "Public", shared_access_key_enabled = true }
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
