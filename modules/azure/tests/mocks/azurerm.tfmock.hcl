# The provider validates id shapes even through the mock, so every id another resource consumes is well formed.
mock_data "azurerm_client_config" {
  defaults = {
    tenant_id       = "00000000-0000-0000-0000-000000000001"
    subscription_id = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
    client_id       = "00000000-0000-0000-0000-000000000004"
  }
}

mock_resource "azurerm_resource_group" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev" }
}

mock_resource "azurerm_virtual_network" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/virtualNetworks/vnet-platformdev" }
}

mock_resource "azurerm_subnet" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/virtualNetworks/vnet-platformdev/subnets/snet-platformdev-nodes" }
}

mock_resource "azurerm_nat_gateway" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/natGateways/ng-platformdev" }
}

mock_resource "azurerm_public_ip" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/publicIPAddresses/pip-platformdev" }
}

mock_resource "azurerm_network_security_group" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev-nodes/providers/Microsoft.Network/networkSecurityGroups/nsg-platformdev-nodes" }
}

mock_resource "azurerm_network_interface" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev-nodes/providers/Microsoft.Network/networkInterfaces/nic-platformdev-server" }
}

mock_resource "azurerm_lb" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/loadBalancers/lb-platformdev-api" }
}

mock_resource "azurerm_lb_backend_address_pool" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/loadBalancers/lb-platformdev-api/backendAddressPools/servers" }
}

mock_resource "azurerm_lb_probe" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/loadBalancers/lb-platformdev-api/probes/tcp-6443" }
}

mock_resource "azurerm_user_assigned_identity" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-platformdev" }
}

mock_resource "azurerm_key_vault" {
  defaults = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.KeyVault/vaults/kv-platformdev"
    vault_uri = "https://kv-platformdev.vault.usgovcloudapi.net/"
  }
}

mock_resource "azurerm_key_vault_secret" {
  defaults = {
    id                      = "https://kv-platformdev.vault.usgovcloudapi.net/secrets/secret/0123456789abcdef0123456789abcdef"
    resource_versionless_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.KeyVault/vaults/kv-platformdev/secrets/secret"
  }
}

mock_resource "azurerm_storage_account" {
  defaults = {
    id                    = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Storage/storageAccounts/acmeplatformdev"
    primary_web_endpoint  = "https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/"
    primary_blob_endpoint = "https://acmeplatformdevoidc.blob.core.usgovcloudapi.net/"
  }
}

mock_resource "azurerm_linux_virtual_machine" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev-nodes/providers/Microsoft.Compute/virtualMachines/platformdev-server-0" }
}

mock_resource "azurerm_managed_disk" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev-nodes/providers/Microsoft.Compute/disks/disk-platformdev-server-0-etcd" }
}

mock_resource "azurerm_storage_container" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Storage/storageAccounts/acmeplatformdev/blobServices/default/containers/etcd-snapshots" }
}
