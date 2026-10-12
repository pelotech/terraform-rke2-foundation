# Group ownership is independent of where nodes and workloads are placed.
mock_provider "azurerm" {
  source = "./tests/mocks"

  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-customer-nodes"
      location = "usgovvirginia"
    }
  }
}

run "reuse_customer_group" {
  command = plan
  variables {
    resource_group      = { name = "rg-customer-nodes", create = false }
    node_resource_group = { name = "rg-customer-nodes", create = false }
  }
  assert {
    condition     = length(azurerm_resource_group.this) == 0 && length(azurerm_resource_group.nodes) == 0
    error_message = "Reusing a customer group must not create or manage either resource group."
  }
  assert {
    condition     = azurerm_linux_virtual_machine.server[0].resource_group_name == "rg-customer-nodes" && azurerm_key_vault.this.resource_group_name == "rg-customer-nodes" && output.cloud_config_resolved.resourceGroup == "rg-customer-nodes"
    error_message = "Nodes, workloads and the cloud provider must use the existing customer group."
  }
  assert {
    condition     = azurerm_role_assignment.server["node_resource_group"].scope == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-customer-nodes" && azurerm_role_assignment.agent["node_resource_group"].scope == azurerm_role_assignment.server["node_resource_group"].scope
    error_message = "Node identities must receive permissions on the existing node group."
  }
}

run "reuse_separate_node_group" {
  command = plan
  variables {
    node_resource_group = { name = "rg-customer-nodes", create = false }
  }
  assert {
    condition     = length(azurerm_resource_group.this) == 1 && length(azurerm_resource_group.nodes) == 0 && output.resource_group_name == "rg-platformdev" && output.node_resource_group_name == "rg-customer-nodes"
    error_message = "The module can create its workload group while reusing a separate node group."
  }
}

run "created_groups_carry_the_given_names" {
  command = plan
  assert {
    condition     = length(azurerm_resource_group.this) == 1 && azurerm_resource_group.this[0].name == "rg-platformdev" && length(azurerm_resource_group.nodes) == 1 && azurerm_resource_group.nodes[0].name == "rg-platformdev-nodes"
    error_message = "resource_group.name and node_resource_group.name are the names, nothing is generated"
  }
  assert {
    condition     = output.resource_group_name == "rg-platformdev" && output.node_resource_group_name == "rg-platformdev-nodes"
    error_message = "the outputs echo the given names"
  }
}
