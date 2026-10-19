# Agent pools: an optional load balancer backend pool per scale set.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "backend_pool_ids_reach_the_scale_set" {
  command = plan
  variables {
    agent_pools = {
      general = {
        vm_size                                = "Standard_D4s_v5"
        load_balancer_backend_address_pool_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/loadBalancers/lbi-platformdev-ingress/backendAddressPools/bp-general"]
      }
      labs = { vm_size = "Standard_D4s_v5" }
    }
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["general"].network_interface[0].ip_configuration[0].load_balancer_backend_address_pool_ids == toset(["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/loadBalancers/lbi-platformdev-ingress/backendAddressPools/bp-general"])
    error_message = "the given pool id lands on the scale set's primary ip configuration"
  }
  assert {
    condition     = length(azurerm_linux_virtual_machine_scale_set.agent["labs"].network_interface[0].ip_configuration[0].load_balancer_backend_address_pool_ids) == 0
    error_message = "a pool without the field joins no backend pool"
  }
}
