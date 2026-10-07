locals {
  # Must match the service accounts the GitOps layer deploys, or the token exchange fails.
  workload_identities = {
    external_dns = { namespace = "external-dns", service_account = "external-dns-controller" }
    cert_manager = { namespace = "cert-manager", service_account = "cert-manager" }
  }

  workload_identity_enabled = {
    for k in keys(local.workload_identities) : k => coalesce(var.workload_identity.overrides[k].enabled, var.workload_identity.enabled)
  }
  enabled_workload_identities = { for k, v in local.workload_identities : k => v if local.workload_identity_enabled[k] }

  # Keys carry the zone id, so removing one zone never touches the others.
  dns_zone_grants = merge([
    for k in keys(local.enabled_workload_identities) : {
      for id in var.workload_identity.overrides[k].dns_zone_ids : "${k}_${lower(id)}" => { identity = k, zone_id = id }
    }
  ]...)

  # external-dns needs Reader on each zone's resource group. Keys are lowercased so ids differing only by case share a grant; the scope keeps Azure's casing or every plan replaces it.
  external_dns_zone_resource_groups = {
    for scope in [
      for parsed in [for id in var.workload_identity.overrides.external_dns.dns_zone_ids : provider::azurerm::parse_resource_id(id)] :
      "/subscriptions/${parsed.subscription_id}/resourceGroups/${parsed.resource_group_name}"
      if local.workload_identity_enabled.external_dns
    ] : lower(scope) => scope...
  }
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each            = local.enabled_workload_identities
  name                = "id-${var.name}-${replace(each.key, "_", "-")}"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each                  = local.enabled_workload_identities
  name                      = "${var.name}-${replace(each.key, "_", "-")}"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

resource "azurerm_role_assignment" "workload_dns_zone" {
  for_each                         = local.dns_zone_grants
  scope                            = each.value.zone_id
  role_definition_name             = "DNS Zone Contributor"
  principal_id                     = azurerm_user_assigned_identity.workload[each.value.identity].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "external_dns_zone_resource_group" {
  for_each                         = local.external_dns_zone_resource_groups
  scope                            = each.value[0]
  role_definition_name             = "Reader"
  principal_id                     = azurerm_user_assigned_identity.workload["external_dns"].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
