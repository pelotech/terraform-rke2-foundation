# VNet, NAT Gateway, private endpoints, the existing_vnet path and the API private address.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "defaults_create_vnet_and_nat_gateway" {
  command = plan
  variables {
    etcd_backup = { enabled = false }
  }
  assert {
    condition     = length(azurerm_virtual_network.this) == 1 && tolist(azurerm_virtual_network.this[0].address_space)[0] == "10.0.0.0/16"
    error_message = "a VNet with the default cidr must be created"
  }
  assert {
    condition     = azurerm_subnet.nodes[0].address_prefixes[0] == "10.0.0.0/22" && azurerm_subnet.nodes[0].default_outbound_access_enabled == false
    error_message = "the node subnet must use the default range and disable Azure's implicit default outbound"
  }
  assert {
    condition     = length(azurerm_subnet.database) == 0
    error_message = "no database subnet unless vnet.database_subnet_cidr is set"
  }
  assert {
    condition     = length(azurerm_nat_gateway.this) == 1 && length(azurerm_public_ip.nat) == 1 && length(azurerm_subnet_nat_gateway_association.nodes) == 1
    error_message = "the NAT Gateway is the only egress, so it always comes with the module's VNet"
  }
  assert {
    condition     = azurerm_nat_gateway.this[0].sku_name == "Standard" && azurerm_nat_gateway.this[0].idle_timeout_in_minutes == 4 && azurerm_public_ip.nat[0].sku == "Standard" && azurerm_public_ip.nat[0].allocation_method == "Static"
    error_message = "NAT Gateway and its ip are Standard with the default idle timeout"
  }
  assert {
    condition     = azurerm_lb.api.frontend_ip_configuration[0].private_ip_address == "10.0.3.254" && azurerm_lb.api.frontend_ip_configuration[0].private_ip_address_allocation == "Static"
    error_message = "the API load balancer takes the last usable address of the node subnet, out of reach of dynamic allocation"
  }
  assert {
    condition     = length(azurerm_subnet.nodes[0].service_endpoint) == 0
    error_message = "no service endpoints unless blob CSI or vnet.service_endpoints asks"
  }
}

run "nat_public_ip_count_is_honoured" {
  command = plan
  variables {
    nat_gateway = { public_ip_count = 3, idle_timeout_minutes = 10 }
  }
  assert {
    condition     = length(azurerm_public_ip.nat) == 3 && length(azurerm_nat_gateway_public_ip_association.nat) == 3 && azurerm_nat_gateway.this[0].idle_timeout_in_minutes == 10
    error_message = "every public ip must exist and be associated with the NAT Gateway"
  }
}

run "database_subnet_and_service_endpoints" {
  command = plan
  variables {
    etcd_backup = { enabled = false }
    vnet = {
      database_subnet_cidr = "10.0.8.0/24"
      service_endpoints    = ["Microsoft.KeyVault"]
    }
  }
  assert {
    condition     = length(azurerm_subnet.database) == 1 && azurerm_subnet.database[0].address_prefixes[0] == "10.0.8.0/24"
    error_message = "database subnet must be created from vnet.database_subnet_cidr"
  }
  assert {
    condition     = [for e in azurerm_subnet.nodes[0].service_endpoint : e.service] == ["Microsoft.KeyVault"]
    error_message = "vnet.service_endpoints become service endpoints on the node subnet"
  }
}

run "existing_vnet_creates_no_network" {
  command = plan
  variables {
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
      api_private_ip = "10.1.0.4"
    }
  }
  assert {
    condition     = length(azurerm_virtual_network.this) == 0 && length(azurerm_subnet.nodes) == 0 && length(azurerm_nat_gateway.this) == 0 && length(azurerm_public_ip.nat) == 0
    error_message = "existing_vnet must create no VNet, subnet or NAT Gateway"
  }
  assert {
    condition     = azurerm_network_interface.server[0].ip_configuration[0].subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
    error_message = "nodes land in the given subnet"
  }
  assert {
    condition     = azurerm_lb.api.frontend_ip_configuration[0].private_ip_address == "10.1.0.4" && output.api_private_ip == "10.1.0.4"
    error_message = "the API address comes from existing_vnet.api_private_ip"
  }
  assert {
    condition     = output.cloud_config_resolved.vnetName == "vnet-shared" && output.cloud_config_resolved.vnetResourceGroup == "rg-net" && output.cloud_config_resolved.subnetName == "snet-nodes"
    error_message = "the cloud provider config names the VNet, its group and the subnet parsed from the subnet id"
  }
}

run "existing_vnet_without_api_private_ip_lets_azure_pick" {
  command = plan
  variables {
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
    }
  }
  assert {
    condition     = azurerm_lb.api.frontend_ip_configuration[0].private_ip_address_allocation == "Dynamic"
    error_message = "without api_private_ip the frontend address is dynamic"
  }
}

run "private_endpoints_land_in_the_node_subnet" {
  command = plan
  variables {
    private_endpoints = {
      vault = {
        resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-shared"
        subresource_names    = ["vault"]
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.usgovcloudapi.net"]
      }
    }
  }
  assert {
    condition     = azurerm_private_endpoint.node_subnet["vault"].name == "pe-platformdev-vault" && azurerm_private_endpoint.node_subnet["vault"].private_service_connection[0].subresource_names[0] == "vault" && azurerm_private_endpoint.node_subnet["vault"].private_service_connection[0].is_manual_connection == false
    error_message = "one private endpoint per key, named pe-<name>-<key>, with an automatic connection"
  }
}
