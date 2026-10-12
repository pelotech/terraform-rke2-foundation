# Attached to every node NIC. cloud-provider-azure adds the rules for LoadBalancer Services here.
resource "azurerm_network_security_group" "nodes" {
  name                = "nsg-${var.name}-nodes"
  location            = var.location
  resource_group_name = local.node_resource_group_name
  tags                = var.tags
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
  resource_group_name         = local.node_resource_group_name
  network_security_group_name = azurerm_network_security_group.nodes.name
}
