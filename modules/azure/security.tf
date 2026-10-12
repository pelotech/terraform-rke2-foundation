locals {
  existing_security_group                 = local.create_vnet ? null : provider::azurerm::parse_resource_id(var.network.existing.security_group_id)
  node_security_group_id                  = local.create_vnet ? azurerm_network_security_group.nodes[0].id : var.network.existing.security_group_id
  node_security_group_name                = local.create_vnet ? azurerm_network_security_group.nodes[0].name : local.existing_security_group.resource_name
  node_security_group_resource_group_name = local.create_vnet ? local.node_resource_group_name : local.existing_security_group.resource_group_name
}

# On the node subnet, never on a NIC. cloud-provider-azure adds the rules for LoadBalancer Services here.
resource "azurerm_network_security_group" "nodes" {
  count               = local.create_vnet ? 1 : 0
  name                = "nsg-${var.name}-nodes"
  location            = var.location
  resource_group_name = local.node_resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  count                     = local.create_vnet ? 1 : 0
  subnet_id                 = azurerm_subnet.nodes[0].id
  network_security_group_id = azurerm_network_security_group.nodes[0].id
}

# Only a public frontend needs a rule: VNet traffic and load balancer probes pass Azure's default rules.
resource "azurerm_network_security_rule" "api_server" {
  count                       = var.cluster_endpoint.public ? 1 : 0
  name                        = "AllowApiServerInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(local.api_ports.api)
  source_address_prefixes     = var.cluster_endpoint.authorized_ip_ranges
  destination_address_prefix  = "*"
  resource_group_name         = local.node_security_group_resource_group_name
  network_security_group_name = local.node_security_group_name
}
