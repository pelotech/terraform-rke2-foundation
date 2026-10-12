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
    create_resource_group      = false
    create_node_resource_group = false
    resource_group_name        = "rg-customer-nodes"
    node_resource_group_name   = "rg-customer-nodes"
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
    create_node_resource_group = false
    node_resource_group_name   = "rg-customer-nodes"
  }
  assert {
    condition     = length(azurerm_resource_group.this) == 1 && length(azurerm_resource_group.nodes) == 0 && output.resource_group_name == "rg-platformdev" && output.node_resource_group_name == "rg-customer-nodes"
    error_message = "The module can create its workload group while reusing a separate node group."
  }
}

run "default_keeps_node_group_owned" {
  command = plan
  assert {
    condition     = length(azurerm_resource_group.nodes) == 1 && output.node_resource_group_name == "rg-platformdev-nodes"
    error_message = "Existing consumers must retain ownership of their node group by default."
  }
}
