# Attached to every node NIC. cloud-provider-azure adds the rules for LoadBalancer Services here.
resource "azurerm_network_security_group" "nodes" {
  name                = "nsg-${var.name}-nodes"
  location            = var.location
  resource_group_name = azurerm_resource_group.nodes.name
  tags                = var.tags
}

# Only a public frontend needs a rule: VNet traffic and load balancer probes pass Azure's default rules.
resource "azurerm_network_security_rule" "api_server" {
  count                       = var.cluster_endpoint_public_access ? 1 : 0
  name                        = "AllowApiServerInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(local.api_ports.api)
  source_address_prefix       = length(var.cluster_endpoint_authorized_ip_ranges) > 0 ? null : "Internet"
  source_address_prefixes     = length(var.cluster_endpoint_authorized_ip_ranges) > 0 ? var.cluster_endpoint_authorized_ip_ranges : null
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.nodes.name
  network_security_group_name = azurerm_network_security_group.nodes.name
}
