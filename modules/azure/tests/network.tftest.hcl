# VNet, NAT Gateway, private endpoints, the existing network path and the API private address.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "created_network_has_a_vnet_and_a_nat_gateway" {
  command = plan
  variables {
    etcd_backup = null
  }
  assert {
    condition     = length(azurerm_virtual_network.this) == 1 && tolist(azurerm_virtual_network.this[0].address_space)[0] == "10.0.0.0/16"
    error_message = "a VNet with the default address space must be created"
  }
  assert {
    condition     = azurerm_subnet.nodes[0].address_prefixes[0] == "10.0.0.0/22" && azurerm_subnet.nodes[0].default_outbound_access_enabled == false
    error_message = "the node subnet must use the default range and disable Azure's implicit default outbound"
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
    error_message = "no service endpoints unless blob CSI, etcd backup or network.create.service_endpoints asks"
  }
}

run "created_network_settings_pass_through" {
  command = plan
  variables {
    etcd_backup = null
    network = {
      create = {
        address_space     = "10.10.0.0/16"
        node_subnet       = "10.10.4.0/22"
        service_endpoints = ["Microsoft.KeyVault"]
        nat_gateway       = { public_ip_count = 3, idle_timeout_minutes = 10 }
      }
    }
  }
  assert {
    condition     = tolist(azurerm_virtual_network.this[0].address_space)[0] == "10.10.0.0/16" && azurerm_subnet.nodes[0].address_prefixes[0] == "10.10.4.0/22" && azurerm_lb.api.frontend_ip_configuration[0].private_ip_address == "10.10.7.254"
    error_message = "address space and node subnet are the given ranges, and the API address follows the subnet"
  }
  assert {
    condition     = length(azurerm_public_ip.nat) == 3 && length(azurerm_nat_gateway_public_ip_association.nat) == 3 && azurerm_nat_gateway.this[0].idle_timeout_in_minutes == 10
    error_message = "every public ip must exist and be associated with the NAT Gateway"
  }
  assert {
    condition     = [for e in azurerm_subnet.nodes[0].service_endpoint : e.service] == ["Microsoft.KeyVault"]
    error_message = "network.create.service_endpoints become service endpoints on the node subnet"
  }
}

run "existing_network_creates_nothing" {
  command = plan
  variables {
    network = {
      existing = {
        vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
        api_private_ip = "10.1.0.4"
      }
    }
  }
  assert {
    condition     = length(azurerm_virtual_network.this) == 0 && length(azurerm_subnet.nodes) == 0 && length(azurerm_nat_gateway.this) == 0 && length(azurerm_public_ip.nat) == 0
    error_message = "network.existing must create no VNet, subnet or NAT Gateway"
  }
  assert {
    condition     = azurerm_network_interface.server[0].ip_configuration[0].subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
    error_message = "nodes land in the given subnet"
  }
  assert {
    condition     = azurerm_lb.api.frontend_ip_configuration[0].private_ip_address == "10.1.0.4" && output.api_private_ip == "10.1.0.4"
    error_message = "the API address comes from network.existing.api_private_ip"
  }
  assert {
    condition     = output.cloud_config_resolved.vnetName == "vnet-shared" && output.cloud_config_resolved.vnetResourceGroup == "rg-net" && output.cloud_config_resolved.subnetName == "snet-nodes"
    error_message = "the cloud provider config names the VNet, its group and the subnet parsed from the subnet id"
  }
  assert {
    condition     = output.vnet_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared" && length(output.nat_gateway_public_ips) == 0
    error_message = "vnet_id echoes the existing VNet and there are no NAT addresses"
  }
}

run "existing_network_without_api_private_ip_lets_azure_pick" {
  command = plan
  variables {
    network = {
      existing = {
        vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
      }
    }
  }
  assert {
    condition     = azurerm_lb.api.frontend_ip_configuration[0].private_ip_address_allocation == "Dynamic"
    error_message = "without api_private_ip the frontend address is dynamic"
  }
}

run "cluster_network_defaults_and_overrides" {
  command = plan
  variables {
    cluster_network = { service_cidr = "10.200.0.0/16", pod_cidr = "10.201.0.0/16" }
  }
  assert {
    condition     = output.cluster_service_cidr == "10.200.0.0/16" && output.cluster_pod_cidr == "10.201.0.0/16" && output.dns_service_ip_resolved == "10.200.0.10"
    error_message = "the Kubernetes ranges pass through and the DNS address is the tenth of the service range"
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
