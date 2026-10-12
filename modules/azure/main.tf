data "azurerm_client_config" "current" {}

locals {
  shared_resource_group = var.resource_group.name == var.node_resource_group.name

  node_resource_group_name = coalesce(
    one(azurerm_resource_group.nodes[*].name),
    one(data.azurerm_resource_group.nodes[*].name),
  )
  node_resource_group_id = coalesce(
    one(azurerm_resource_group.nodes[*].id),
    one(data.azurerm_resource_group.nodes[*].id),
  )

  # Prefer the created workload group, then the shared node group, then the existing group.
  resource_group_name = coalesce(
    one(azurerm_resource_group.this[*].name),
    local.shared_resource_group ? local.node_resource_group_name : null,
    var.resource_group.name,
  )

  # environment is the name cloud-provider-azure and kubelogin share.
  azure_clouds = {
    public = {
      environment        = "AzurePublicCloud"
      entra_login_host   = "login.microsoftonline.com"
      key_vault_audience = "https://vault.azure.net"
    }
    usgovernment = {
      environment        = "AzureUSGovernmentCloud"
      entra_login_host   = "login.microsoftonline.us"
      key_vault_audience = "https://vault.usgovcloudapi.net"
    }
  }
  azure_cloud = local.azure_clouds[var.azure_cloud]

  os_disk_types = ["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"]
  # Premium disks need a size whose suffix carries an s, such as D4s_v5 or D4ds_v4; Azure refuses the pair only at apply time.
  premium_capable_size = "^Standard_[A-Z]+[0-9]+[a-z]*s[a-z]*(_v[0-9]+)?$"
}

resource "azurerm_resource_group" "this" {
  count    = var.resource_group.create ? 1 : 0
  name     = var.resource_group.name
  location = var.location
  tags     = var.tags
}

# Nodes, scale sets and cloud-provider/CSI resources use this group; workloads can share it.
resource "azurerm_resource_group" "nodes" {
  count    = var.node_resource_group.create ? 1 : 0
  name     = var.node_resource_group.name
  location = var.location
  tags     = var.tags
}

# The platform owns this group; reading it does not import it into cluster state.
data "azurerm_resource_group" "nodes" {
  count = var.node_resource_group.create ? 0 : 1
  name  = var.node_resource_group.name
}

# Preserve the node group address for existing consumers that keep the default.
moved {
  from = azurerm_resource_group.nodes
  to   = azurerm_resource_group.nodes[0]
}
