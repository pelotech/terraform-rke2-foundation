# runtime_credential: nodes authenticate with a service principal, so the module creates no identity, grant or vault secret.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "service_principal_replaces_identities_grants_and_vault_secrets" {
  command = apply
  variables {
    runtime_credential = { client_id = "00000000-0000-0000-0000-000000000005", client_secret = "sentinel-client-secret" }
    etcd_backup        = { storage_account_name = "acmeplatformdevetcd" }
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.server) == 0 && length(azurerm_user_assigned_identity.agent) == 0 && length(azurerm_role_assignment.server) == 0 && length(azurerm_role_assignment.agent) == 0 && length(azurerm_role_assignment.key_vault_admin) == 0
    error_message = "no identity and no role assignment: the applying principal needs neither right"
  }
  assert {
    condition     = length(azurerm_key_vault_secret.node) == 0 && length(azurerm_key_vault_secret.ssh_private_key) == 0 && azurerm_key_vault.this.name == "kv-platformdev"
    error_message = "the vault stays but holds nothing"
  }
  assert {
    condition     = length(azurerm_linux_virtual_machine.server[0].identity) == 0 && length(azurerm_linux_virtual_machine_scale_set.agent["general"].identity) == 0
    error_message = "no identity is attached to the nodes"
  }
  assert {
    condition     = output.cloud_config_resolved.useManagedIdentityExtension == false && output.cloud_config_resolved.aadClientId == "00000000-0000-0000-0000-000000000005" && !contains(keys(output.cloud_config_resolved), "aadClientSecret") && !contains(keys(output.cloud_config_resolved), "userAssignedIdentityID")
    error_message = "the cloud config names the principal; the output hides its secret"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "aadClientSecret") && strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), base64encode(module.bootstrap.server_secret_contents["rke2-token"])) && strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "oauth2/token")
    error_message = "servers carry the cloud config secret, the join tokens and the client-credentials token script"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), base64encode(module.bootstrap.server_secret_contents["rke2-agent-token"])) && !strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), base64encode(module.bootstrap.server_secret_contents["rke2-token"])) && !strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), "sentinel-client-secret")
    error_message = "agents carry only the agent token: no server token and no client secret"
  }
  assert {
    condition     = output.server_identity_client_id == null && output.agent_identity_client_id == null && output.server_identity_id == null
    error_message = "identity outputs are null"
  }
}
