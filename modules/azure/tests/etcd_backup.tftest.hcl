# Hourly upload of etcd snapshots to a private storage account.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "private_account_container_and_grant_by_default" {
  command = apply
  assert {
    condition     = azurerm_storage_account.etcd_backup[0].name == "acmeplatformdevetcd" && azurerm_storage_account.etcd_backup[0].shared_access_key_enabled == false && azurerm_storage_account.etcd_backup[0].allow_nested_items_to_be_public == false && azurerm_storage_account.etcd_backup[0].blob_properties[0].versioning_enabled == true && azurerm_storage_account.etcd_backup[0].blob_properties[0].delete_retention_policy[0].days == 30
    error_message = "a dedicated account: keys off, nothing public, versioning and 30 days of soft delete"
  }
  assert {
    condition     = azurerm_storage_account_network_rules.etcd_backup[0].default_action == "Deny" && tolist(azurerm_storage_account_network_rules.etcd_backup[0].virtual_network_subnet_ids) == tolist([azurerm_subnet.nodes[0].id]) && contains([for e in azurerm_subnet.nodes[0].service_endpoint : e.service], "Microsoft.Storage")
    error_message = "only the node subnet reaches the account, through the storage service endpoint"
  }
  assert {
    condition     = azurerm_storage_container.etcd_backup[0].name == "etcd-snapshots" && azurerm_storage_container.etcd_backup[0].container_access_type == "private" && azurerm_storage_management_policy.etcd_backup[0].rule[0].actions[0].base_blob[0].delete_after_days_since_modification_greater_than == 30
    error_message = "one private container with a 30 day lifecycle rule"
  }
  assert {
    condition     = azurerm_role_assignment.server["etcd_backup"].role_definition_name == "Storage Blob Data Contributor" && azurerm_role_assignment.server["etcd_backup"].scope == azurerm_storage_container.etcd_backup[0].id
    error_message = "the server identity writes to the container only"
  }
  assert {
    condition     = endswith(output.etcd_backup_container_url, "/etcd-snapshots")
    error_message = "the container URL output ends with the container name"
  }
}

run "disabled_creates_nothing" {
  command = plan
  variables {
    etcd_backup = { enabled = false }
  }
  assert {
    condition     = length(azurerm_storage_account.etcd_backup) == 0 && length(azurerm_storage_container.etcd_backup) == 0 && !contains(keys(azurerm_role_assignment.server), "etcd_backup")
    error_message = "etcd_backup.enabled = false creates no account, container or grant"
  }
}

run "retention_in_range" {
  command = plan
  variables {
    etcd_backup = { retention_days = 0 }
  }
  expect_failures = [var.etcd_backup]
}
