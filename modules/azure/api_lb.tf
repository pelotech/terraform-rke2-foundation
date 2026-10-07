locals {
  api_ports = { api = 6443, supervisor = 9345 }
  # Unique per region without a consumer choice: the subscription and group make the hash.
  api_dns_label           = coalesce(var.cluster_endpoint_dns_label, "${var.name}-${substr(md5("${data.azurerm_client_config.current.subscription_id}/${local.resource_group_name_wanted}"), 0, 8)}")
  api_private_ip_resolved = coalesce(local.api_private_ip, azurerm_lb.api.private_ip_address)
  api_host                = var.cluster_endpoint_public_access ? azurerm_public_ip.api[0].fqdn : local.api_private_ip_resolved
  cluster_endpoint        = "https://${local.api_host}:${local.api_ports.api}"

  # One probe and rule per balancer and port. The public balancer fronts the API port only.
  api_lb_rules = merge(
    { for name, port in local.api_ports : name => { loadbalancer_id = azurerm_lb.api.id, pool_id = azurerm_lb_backend_address_pool.api.id, port = port, public = false } },
    var.cluster_endpoint_public_access ? {
      public_api = { loadbalancer_id = azurerm_lb.api_public[0].id, pool_id = azurerm_lb_backend_address_pool.api_public[0].id, port = local.api_ports.api, public = true }
    } : {},
  )
}

# The fixed registration address: every node joins through it and the API answers on it.
resource "azurerm_lb" "api" {
  name                = "lb-${var.name}-api"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = "api"
    subnet_id                     = local.node_subnet_id
    private_ip_address_allocation = local.api_private_ip == null ? "Dynamic" : "Static"
    private_ip_address            = local.api_private_ip
  }
}

resource "azurerm_lb_backend_address_pool" "api" {
  name            = "servers"
  loadbalancer_id = azurerm_lb.api.id
}

resource "azurerm_public_ip" "api" {
  count               = var.cluster_endpoint_public_access ? 1 : 0
  name                = "pip-${var.name}-api"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"
  domain_name_label   = local.api_dns_label
  tags                = var.tags
}

resource "azurerm_lb" "api_public" {
  count               = var.cluster_endpoint_public_access ? 1 : 0
  name                = "lb-${var.name}-api-public"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "api"
    public_ip_address_id = azurerm_public_ip.api[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "api_public" {
  count           = var.cluster_endpoint_public_access ? 1 : 0
  name            = "servers"
  loadbalancer_id = azurerm_lb.api_public[0].id
}

resource "azurerm_lb_probe" "api" {
  for_each        = local.api_lb_rules
  name            = "tcp-${each.value.port}"
  loadbalancer_id = each.value.loadbalancer_id
  protocol        = "Tcp"
  port            = each.value.port
}

resource "azurerm_lb_rule" "api" {
  for_each                       = local.api_lb_rules
  name                           = "tcp-${each.value.port}"
  loadbalancer_id                = each.value.loadbalancer_id
  protocol                       = "Tcp"
  frontend_port                  = each.value.port
  backend_port                   = each.value.port
  frontend_ip_configuration_name = "api"
  backend_address_pool_ids       = [each.value.pool_id]
  probe_id                       = azurerm_lb_probe.api[each.key].id
  idle_timeout_in_minutes        = 30
  # Egress stays on the NAT Gateway.
  disable_outbound_snat = each.value.public
}
