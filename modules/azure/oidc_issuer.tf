locals {
  oidc_issuer_enabled       = anytrue(values(local.workload_identity_enabled))
  oidc_storage_account_name = coalesce(var.workload_identity.oidc_storage_account_name, substr("${local.storage_account_name_stem}oidc", 0, 24))
  oidc_issuer_url           = one(azurerm_storage_account.oidc[*].primary_web_endpoint)
}

# Serves the discovery document and JWKS Entra reads. The servers upload them after RKE2 starts.
resource "azurerm_storage_account" "oidc" {
  count                           = local.oidc_issuer_enabled ? 1 : 0
  name                            = local.oidc_storage_account_name
  resource_group_name             = local.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Static website hosting is a blob data-plane setting Terraform sets with the account key; the account only ever holds public documents.
  shared_access_key_enabled = true
  tags                      = var.tags
}

resource "azurerm_storage_account_static_website" "oidc" {
  count              = local.oidc_issuer_enabled ? 1 : 0
  storage_account_id = azurerm_storage_account.oidc[0].id
  # The provider requires a document name; nothing serves it.
  index_document = "index.html"
}
