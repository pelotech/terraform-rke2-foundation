data "azurerm_client_config" "current" {}

locals {
  resource_group_name_wanted = coalesce(var.resource_group_name, "rg-${var.name}")
  # Read through the resource so everything that uses the name waits for the group to exist.
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name_wanted

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

  storage_account_name_stem = lower(replace("${try(var.tags.Owner, "")}${var.name}", "/[^A-Za-z0-9]/", ""))
  os_disk_types             = ["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"]
  # Premium disks need a size whose suffix carries an s, such as D4s_v5 or D4ds_v4; Azure refuses the pair only at apply time.
  premium_capable_size = "^Standard_[A-Z]+[0-9]+[a-z]*s[a-z]*(_v[0-9]+)?$"
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.resource_group_name_wanted
  location = var.location
  tags     = var.tags
}

# Nodes, scale sets and what the cloud provider and CSI driver create live apart, so identities get Contributor here only.
resource "azurerm_resource_group" "nodes" {
  name     = coalesce(var.node_resource_group_name, "rg-${var.name}-nodes")
  location = var.location
  tags     = var.tags
}
