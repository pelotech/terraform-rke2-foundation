locals {
  server_zones  = [for i in range(var.servers.count) : length(var.servers.zones) > 0 ? var.servers.zones[i % length(var.servers.zones)] : null]
  etcd_disk_lun = 0
}

resource "azurerm_network_interface" "server" {
  count               = var.servers.count
  name                = "nic-${var.name}-server-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.nodes.name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = local.node_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "server" {
  count                     = var.servers.count
  network_interface_id      = azurerm_network_interface.server[count.index].id
  network_security_group_id = azurerm_network_security_group.nodes.id

  # One write at a time per NIC: the provider locks pool associations by name and this one by id, so they overlap
  # and Azure cancels one of the two.
  depends_on = [
    azurerm_network_interface_backend_address_pool_association.server_api,
    azurerm_network_interface_backend_address_pool_association.server_api_public,
  ]
}

resource "azurerm_network_interface_backend_address_pool_association" "server_api" {
  count                   = var.servers.count
  network_interface_id    = azurerm_network_interface.server[count.index].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.api.id
}

resource "azurerm_network_interface_backend_address_pool_association" "server_api_public" {
  count                   = var.cluster_endpoint_public_access ? var.servers.count : 0
  network_interface_id    = azurerm_network_interface.server[count.index].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.api_public[0].id
}

# etcd gets a Premium SSD v2 disk of its own: no host cache, unlike the OS disk, and no contention with image pulls.
resource "azurerm_managed_disk" "etcd" {
  count                = var.servers.etcd_disk.enabled ? var.servers.count : 0
  name                 = "disk-${var.name}-server-${count.index}-etcd"
  location             = var.location
  resource_group_name  = azurerm_resource_group.nodes.name
  zone                 = local.server_zones[count.index]
  storage_account_type = "PremiumV2_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.servers.etcd_disk.size_gb
  disk_iops_read_write = var.servers.etcd_disk.iops
  disk_mbps_read_write = var.servers.etcd_disk.mbps
  tags                 = var.tags

  lifecycle {
    # A new VM must start from an empty etcd directory, so the disk follows its VM.
    replace_triggered_by = [azurerm_linux_virtual_machine.server[count.index].id]
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "etcd" {
  count              = var.servers.etcd_disk.enabled ? var.servers.count : 0
  managed_disk_id    = azurerm_managed_disk.etcd[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.server[count.index].id
  lun                = local.etcd_disk_lun
  caching            = "None"
}

# cloud-provider-azure looks standalone VMs up by the Kubernetes node name, so the VM name is the hostname.
resource "azurerm_linux_virtual_machine" "server" {
  count                           = var.servers.count
  name                            = "${var.name}-server-${count.index}"
  computer_name                   = "${var.name}-server-${count.index}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.nodes.name
  size                            = var.servers.vm_size
  zone                            = local.server_zones[count.index]
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.server[count.index].id]
  custom_data                     = base64encode(count.index == 0 ? module.bootstrap.server_user_data.init_candidate : module.bootstrap.server_user_data.member)
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.server.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.servers.os_disk_type
    disk_size_gb         = var.servers.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  dynamic "plan" {
    for_each = var.image.plan == null ? [] : [var.image.plan]
    content {
      name      = plan.value.name
      product   = plan.value.product
      publisher = plan.value.publisher
    }
  }

  boot_diagnostics {}

  lifecycle {
    # A changed cloud-init must not replace every server at once; see the README section "Replace a server".
    ignore_changes = [custom_data]
  }

  # The NIC is in its pools and NSG before the VM boots, and leaves them only after the VM is gone: Azure cancels a NIC
  # update that overlaps the VM delete.
  depends_on = [
    azurerm_role_assignment.server,
    azurerm_key_vault_secret.node,
    azurerm_subnet_nat_gateway_association.nodes,
    azurerm_lb_rule.api,
    azurerm_network_interface_backend_address_pool_association.server_api,
    azurerm_network_interface_backend_address_pool_association.server_api_public,
    azurerm_network_interface_security_group_association.server,
  ]
}
