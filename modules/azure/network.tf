locals {
  create_vnet    = var.existing_vnet == null
  node_subnet_id = local.create_vnet ? azurerm_subnet.nodes[0].id : var.existing_vnet.node_subnet_id
  # The last usable address: dynamic allocation starts at the bottom of the subnet and would take a low one first.
  api_private_ip = local.create_vnet ? cidrhost(var.vnet.node_subnet_cidr, -2) : var.existing_vnet.api_private_ip

  existing_subnet          = local.create_vnet ? null : provider::azurerm::parse_resource_id(var.existing_vnet.node_subnet_id)
  vnet_name                = local.create_vnet ? azurerm_virtual_network.this[0].name : local.existing_subnet.parent_resources["virtualNetworks"]
  vnet_resource_group_name = local.create_vnet ? local.resource_group_name : local.existing_subnet.resource_group_name
  node_subnet_name         = local.create_vnet ? azurerm_subnet.nodes[0].name : local.existing_subnet.resource_name

  # CIDRs each variable must not overlap; the VNet counts only when the module creates it.
  pod_cidr_must_avoid     = concat([var.service_cidr], local.create_vnet ? [var.vnet.cidr] : [])
  service_cidr_must_avoid = local.create_vnet ? [var.vnet.cidr] : []
}

resource "azurerm_virtual_network" "this" {
  count               = local.create_vnet ? 1 : 0
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = [var.vnet.cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  count                = local.create_vnet ? 1 : 0
  name                 = "snet-${var.name}-nodes"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.vnet.node_subnet_cidr]
  # Egress is the NAT Gateway, never Azure's implicit default outbound.
  default_outbound_access_enabled = false

  dynamic "service_endpoint" {
    for_each = toset(concat(var.vnet.service_endpoints, local.blob_csi_node_subnet_only || local.etcd_backup_enabled ? ["Microsoft.Storage"] : []))
    content {
      service = service_endpoint.value
    }
  }
}

resource "azurerm_subnet" "database" {
  count                           = local.create_vnet && var.vnet.database_subnet_cidr != null ? 1 : 0
  name                            = "snet-${var.name}-database"
  resource_group_name             = local.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this[0].name
  address_prefixes                = [var.vnet.database_subnet_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "nat" {
  count               = local.create_vnet ? var.nat_gateway.public_ip_count : 0
  name                = "pip-${var.name}-nat-${count.index}"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge(var.tags, {
    Name = "nat-${var.name}-${count.index}"
  })
}

resource "azurerm_nat_gateway" "this" {
  count                   = local.create_vnet ? 1 : 0
  name                    = "ng-${var.name}"
  location                = var.location
  resource_group_name     = local.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway.idle_timeout_minutes
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  count                = local.create_vnet ? var.nat_gateway.public_ip_count : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  count          = local.create_vnet ? 1 : 0
  subnet_id      = azurerm_subnet.nodes[0].id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

resource "azurerm_private_endpoint" "node_subnet" {
  for_each            = var.private_endpoints
  name                = "pe-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = local.resource_group_name
  subnet_id           = local.node_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = each.value.subresource_names
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = each.value.private_dns_zone_ids
  }
}
