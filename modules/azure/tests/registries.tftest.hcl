# A private registry: its config is a node secret, its CA a cloud-init file.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "registries_reach_both_roles" {
  command = apply
  variables {
    registries_config = "mirrors:\n  docker.io:\n    endpoint:\n      - https://mirror.example\n"
    registry_ca_pem   = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
  }
  assert {
    condition     = contains(keys(azurerm_key_vault_secret.node), "rke2-registries") && contains(keys(azurerm_role_assignment.agent), "rke2-registries")
    error_message = "the registries config is a Key Vault secret that the agent identity may read"
  }
  assert {
    condition = alltrue(concat(
      [for server in azurerm_linux_virtual_machine.server : strcontains(base64decode(server.custom_data), "/etc/rancher/rke2/registry-ca.pem") && !strcontains(base64decode(server.custom_data), "mirror.example")],
      [for pool in azurerm_linux_virtual_machine_scale_set.agent : strcontains(base64decode(pool.custom_data), "/etc/rancher/rke2/registry-ca.pem") && !strcontains(base64decode(pool.custom_data), "mirror.example")],
    ))
    error_message = "the CA reaches every node through cloud-init and the config never does"
  }
}

run "registries_are_optional" {
  command = plan
  assert {
    condition     = !contains(keys(azurerm_key_vault_secret.node), "rke2-registries")
    error_message = "without registries_config there is no registries secret"
  }
}
