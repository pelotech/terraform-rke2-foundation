# Key Vault, the secrets every node reads at boot, the SSH key and the node identities' grants.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "key_vault_defaults" {
  command = plan
  assert {
    condition     = azurerm_key_vault.this.name == "kv-platformdev" && azurerm_key_vault.this.rbac_authorization_enabled == true && azurerm_key_vault.this.purge_protection_enabled == true && azurerm_key_vault.this.soft_delete_retention_days == 90
    error_message = "a vault named kv-<name> with RBAC, purge protection and 90-day soft delete"
  }
  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == true
    error_message = "key_vault.network_access Public keeps the vault reachable from the nodes"
  }
  assert {
    condition     = length(azurerm_role_assignment.key_vault_admin) == 0
    error_message = "no Secrets Officer grants unless admin_object_ids lists principals"
  }
}

run "key_vault_name_is_truncated_and_overridable" {
  command = plan
  variables {
    name = "a-long-cluster-name-for-vaults"
  }
  assert {
    condition     = azurerm_key_vault.this.name == "kv-a-long-cluster-name-f" && length(azurerm_key_vault.this.name) <= 24
    error_message = "the generated vault name fits 24 characters"
  }
}

run "key_vault_override_and_admins" {
  command = plan
  variables {
    key_vault = { name = "kv-custom", network_access = "Private", admin_object_ids = ["11111111-1111-1111-1111-111111111111"] }
  }
  assert {
    condition     = azurerm_key_vault.this.name == "kv-custom" && azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "name and network access pass through"
  }
  assert {
    condition     = azurerm_role_assignment.key_vault_admin["11111111-1111-1111-1111-111111111111"].role_definition_name == "Key Vault Secrets Officer"
    error_message = "admins get Secrets Officer, which writing the secrets needs"
  }
}

run "node_secrets_and_generated_ssh_key" {
  command = plan
  assert {
    condition     = length(azurerm_key_vault_secret.node) == 13 && contains(keys(azurerm_key_vault_secret.node), "rke2-tls-etcd-server-ca-key") && contains(keys(azurerm_key_vault_secret.node), "rke2-agent-token")
    error_message = "the eleven CA files and both tokens are vault secrets"
  }
  assert {
    condition     = length(tls_private_key.ssh) == 1 && tls_private_key.ssh[0].algorithm == "RSA" && tls_private_key.ssh[0].rsa_bits == 4096 && length(azurerm_key_vault_secret.ssh_private_key) == 1 && azurerm_key_vault_secret.ssh_private_key[0].name == "ssh-private-key"
    error_message = "without ssh_public_key the module generates an RSA key and keeps the private half in the vault"
  }
}

run "provided_ssh_key_is_used_as_is" {
  command = plan
  variables {
    ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsuGeE3OLSthHDh5i2PothNQJi/8cER9sxcrD32FZWB4frM1a6ax0Br0q/Hx0Dyh5ExAiTPgZ8DBaA2WwI4Ix248xrbcpNNKG9NOi8Qu2/2vqQ7MHYQMbV4esAbvv1u5lJKqe7DgAq8BkHpC31WNaVsRUDLrneAdDnRcZBhnFn9IPvVpZGmcILpimAlwYaxcUgcPVPMDv8eC/HDo4w8FxmkFDZIFDLgXkBhq8PB7ucbqnO2Jcl3l1iRGosQRTgmoS1kvYtrgy5HKJjOtdoJ8BCOabXo0zvTHUjH1TwddswxznADQaGBTSZ6l90jqKb5sK+YyH6UcVx1aWzjCo0ehWt platform"
  }
  assert {
    condition     = length(tls_private_key.ssh) == 0 && length(azurerm_key_vault_secret.ssh_private_key) == 0 && one(azurerm_linux_virtual_machine.server[0].admin_ssh_key).public_key == "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsuGeE3OLSthHDh5i2PothNQJi/8cER9sxcrD32FZWB4frM1a6ax0Br0q/Hx0Dyh5ExAiTPgZ8DBaA2WwI4Ix248xrbcpNNKG9NOi8Qu2/2vqQ7MHYQMbV4esAbvv1u5lJKqe7DgAq8BkHpC31WNaVsRUDLrneAdDnRcZBhnFn9IPvVpZGmcILpimAlwYaxcUgcPVPMDv8eC/HDo4w8FxmkFDZIFDLgXkBhq8PB7ucbqnO2Jcl3l1iRGosQRTgmoS1kvYtrgy5HKJjOtdoJ8BCOabXo0zvTHUjH1TwddswxznADQaGBTSZ6l90jqKb5sK+YyH6UcVx1aWzjCo0ehWt platform"
    error_message = "a provided key creates nothing and lands on the nodes"
  }
}

run "identity_grants" {
  command = plan
  assert {
    condition     = azurerm_user_assigned_identity.server.name == "id-platformdev-server" && azurerm_user_assigned_identity.agent.name == "id-platformdev-agent"
    error_message = "one identity for servers, one for agents"
  }
  assert {
    condition     = azurerm_role_assignment.server["node_resource_group"].role_definition_name == "Contributor" && azurerm_role_assignment.server["node_subnet"].role_definition_name == "Network Contributor" && azurerm_role_assignment.server["key_vault_secrets"].role_definition_name == "Key Vault Secrets User" && azurerm_role_assignment.server["oidc_storage"].role_definition_name == "Storage Blob Data Contributor"
    error_message = "servers run the cloud provider, read every secret and publish the OIDC documents"
  }
  assert {
    condition     = azurerm_role_assignment.agent["node_resource_group"].role_definition_name == "Contributor" && azurerm_role_assignment.agent["rke2-agent-token"].role_definition_name == "Key Vault Secrets User" && !contains(keys(azurerm_role_assignment.agent), "key_vault_secrets")
    error_message = "agents get Contributor on the node group for the disk CSI driver and read only the agent token"
  }
  assert {
    condition     = alltrue([for a in merge(azurerm_role_assignment.server, azurerm_role_assignment.agent) : a.principal_type == "ServicePrincipal" && a.skip_service_principal_aad_check == true])
    error_message = "identity grants skip the Entra replication check, so a fresh identity can be granted in the same apply"
  }
}

run "agent_token_grant_is_scoped_to_that_secret" {
  command = apply
  override_resource {
    target = azurerm_key_vault_secret.node["rke2-agent-token"]
    values = {
      resource_versionless_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.KeyVault/vaults/kv-platformdev/secrets/rke2-agent-token"
    }
  }
  assert {
    condition     = azurerm_role_assignment.agent["rke2-agent-token"].scope == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.KeyVault/vaults/kv-platformdev/secrets/rke2-agent-token"
    error_message = "the agent grant's scope is the agent token secret, not the vault"
  }
}
