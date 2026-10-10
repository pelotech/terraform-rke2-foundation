locals {
  cni_agent_pool = local.cni_node_pool_enabled ? {
    cni = {
      vm_size         = coalesce(var.cni_node_pool.vm_size, var.servers.vm_size)
      node_count      = var.cni_node_pool.node_count
      min_count       = null
      max_count       = null
      zones           = var.cni_node_pool.zones != null ? var.cni_node_pool.zones : var.servers.zones
      os_disk_size_gb = var.cni_node_pool.os_disk_size_gb
      os_disk_type    = var.cni_node_pool.os_disk_type
      labels          = local.cni_node_pool_labels
      taints          = local.cni_node_pool_taints
    }
  } : {}
  agent_pools              = merge(var.agent_pools, local.cni_agent_pool)
  agent_pool_taint_strings = { for pool, cfg in local.agent_pools : pool => [for t in values(cfg.taints) : "${t.key}=${t.value}:${t.effect}"] }
  # The shape the output exposes and the bootstrap consumes, which keeps only labels and taints.
  agent_pools_resolved = {
    for pool, cfg in local.agent_pools : pool => {
      vm_size    = cfg.vm_size
      node_count = cfg.node_count
      min_count  = cfg.min_count
      max_count  = cfg.max_count
      zones      = cfg.zones
      labels     = cfg.labels
      taints     = local.agent_pool_taint_strings[pool]
    }
  }

  # cluster-autoscaler discovers pools by these tags and scales between min and max. A pool at zero has no node
  # to read, so it takes the labels and taints from the node template tags: a slash in a key becomes an underscore.
  agent_pool_autoscaler_tags = {
    for pool, cfg in local.agent_pools : pool => cfg.min_count == null ? {} : merge(
      {
        "cluster-autoscaler-enabled" = "true"
        "cluster-autoscaler-name"    = var.name
        min                          = tostring(cfg.min_count)
        max                          = tostring(cfg.max_count)
      },
      { for k, v in cfg.labels : "k8s.io_cluster-autoscaler_node-template_label_${replace(replace(k, "_", "~2"), "/", "_")}" => v },
      { for _, t in cfg.taints : "k8s.io_cluster-autoscaler_node-template_taint_${replace(replace(t.key, "_", "~2"), "/", "_")}" => "${t.value}:${t.effect}" },
    )
  }
}

resource "azurerm_linux_virtual_machine_scale_set" "agent" {
  for_each             = local.agent_pools
  name                 = "vmss-${var.name}-${each.key}"
  computer_name_prefix = "${var.name}-${each.key}-"
  location             = var.location
  resource_group_name  = azurerm_resource_group.nodes.name
  sku                  = each.value.vm_size
  instances            = each.value.node_count
  zones                = length(each.value.zones) > 0 ? each.value.zones : null
  # Manual: the operator rolls a pool. No overprovisioning: extra instances would join the cluster before Azure removes them.
  upgrade_mode                    = "Manual"
  overprovision                   = false
  single_placement_group          = false
  admin_username                  = var.admin_username
  disable_password_authentication = true
  custom_data                     = base64encode(module.bootstrap.agent_user_data[each.key])
  tags                            = merge(var.tags, local.agent_pool_autoscaler_tags[each.key])

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = each.value.os_disk_type
    disk_size_gb         = each.value.os_disk_size_gb
  }

  source_image_id = var.image.id
  dynamic "source_image_reference" {
    for_each = var.image.id == null ? [var.image] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  dynamic "plan" {
    for_each = var.image.plan == null ? [] : [var.image.plan]
    content {
      name      = plan.value.name
      product   = plan.value.product
      publisher = plan.value.publisher
    }
  }

  network_interface {
    name                      = "primary"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.nodes.id

    ip_configuration {
      name      = "primary"
      primary   = true
      subnet_id = local.node_subnet_id
    }
  }

  boot_diagnostics {}

  lifecycle {
    # cluster-autoscaler owns the size, and cloud-provider-azure owns the load balancer pool membership.
    ignore_changes = [
      instances,
      network_interface[0].ip_configuration[0].load_balancer_backend_address_pool_ids,
    ]
  }

  depends_on = [
    azurerm_role_assignment.agent,
    azurerm_key_vault_secret.node,
    azurerm_subnet_nat_gateway_association.nodes,
  ]
}
