# The OIDC issuer the cluster publishes and the Entra workload identities that trust it.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "issuer_and_both_identities" {
  command = plan
  assert {
    condition     = length(azurerm_storage_account.oidc) == 1 && azurerm_storage_account.oidc[0].name == "acmeplatformdevoidc" && azurerm_storage_account.oidc[0].allow_nested_items_to_be_public == false && azurerm_storage_account.oidc[0].shared_access_key_enabled == true && azurerm_storage_account.oidc[0].min_tls_version == "TLS1_2"
    error_message = "an issuer account with the given name, no public containers, keys on for the static website setting"
  }
  assert {
    condition     = length(azurerm_storage_account_static_website.oidc) == 1
    error_message = "static website hosting serves the discovery document and JWKS"
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.workload) == 2 && azurerm_user_assigned_identity.workload["external_dns"].name == "id-platformdev-external-dns" && azurerm_user_assigned_identity.workload["cert_manager"].name == "id-platformdev-cert-manager"
    error_message = "an identity for each controller listed"
  }
  assert {
    condition     = azurerm_federated_identity_credential.workload["external_dns"].subject == "system:serviceaccount:external-dns:external-dns-controller" && azurerm_federated_identity_credential.workload["cert_manager"].subject == "system:serviceaccount:cert-manager:cert-manager" && tolist(azurerm_federated_identity_credential.workload["external_dns"].audience) == tolist(["api://AzureADTokenExchange"])
    error_message = "federated credential subjects match the GitOps service accounts"
  }
  assert {
    condition     = length(azurerm_role_assignment.workload_dns_zone) == 0 && length(azurerm_role_assignment.external_dns_zone_resource_group) == 0
    error_message = "no DNS grants unless zones are listed"
  }
  assert {
    condition     = output.workload_identity_enabled_resolved == { external_dns = true, cert_manager = true }
    error_message = "introspection reports both"
  }
}

run "null_creates_nothing" {
  command = plan
  variables {
    workload_identity = null
  }
  assert {
    condition     = length(azurerm_storage_account.oidc) == 0 && length(azurerm_storage_account_static_website.oidc) == 0 && length(azurerm_user_assigned_identity.workload) == 0 && !contains(keys(azurerm_role_assignment.server), "oidc_storage")
    error_message = "no issuer account, identities or storage grant"
  }
  assert {
    condition     = !contains(keys(output.server_config_resolved), "kube-apiserver-arg") && output.oidc_issuer_url == null && output.oidc_storage_account_id == null && output.external_dns_client_id == null
    error_message = "no issuer args on the API server and null outputs"
  }
}

run "issuer_without_controllers" {
  command = apply
  variables {
    workload_identity = { storage_account_name = "platformdevoidc" }
  }
  assert {
    condition     = length(azurerm_storage_account.oidc) == 1 && azurerm_storage_account.oidc[0].name == "platformdevoidc" && azurerm_role_assignment.server["oidc_storage"].role_definition_name == "Storage Blob Data Contributor"
    error_message = "the issuer exists on its own, published by the server identity"
  }
  assert {
    condition     = contains(output.server_config_resolved["kube-apiserver-arg"], "service-account-issuer=https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/")
    error_message = "the API server issues tokens for the issuer from day one, so a later controller needs no server change"
  }
  assert {
    condition     = length(azurerm_user_assigned_identity.workload) == 0 && output.external_dns_client_id == null && output.cert_manager_client_id == null && output.workload_identity_enabled_resolved == { external_dns = false, cert_manager = false }
    error_message = "no identity without its controller listed"
  }
}

run "one_controller" {
  command = plan
  variables {
    workload_identity = { storage_account_name = "platformdevoidc", cert_manager = {} }
  }
  assert {
    condition     = sort(keys(azurerm_user_assigned_identity.workload)) == tolist(["cert_manager"]) && length(azurerm_storage_account.oidc) == 1
    error_message = "listing one controller creates that identity only"
  }
}

run "dns_zones_grant_contributor_and_reader" {
  command = plan
  variables {
    workload_identity = {
      storage_account_name = "platformdevoidc"
      external_dns = {
        dns_zone_ids = [
          "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/example.com",
          "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns-b/providers/Microsoft.Network/dnszones/example.org",
        ]
      }
      cert_manager = {
        dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/example.com"]
      }
    }
  }
  assert {
    condition     = length(azurerm_role_assignment.workload_dns_zone) == 3 && azurerm_role_assignment.workload_dns_zone["external_dns_/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/rg-dns-b/providers/microsoft.network/dnszones/example.org"].role_definition_name == "DNS Zone Contributor"
    error_message = "one DNS Zone Contributor per identity and zone, keyed <identity>_<lowercased zone id>"
  }
  assert {
    condition     = length(azurerm_role_assignment.external_dns_zone_resource_group) == 2 && contains(keys(azurerm_role_assignment.external_dns_zone_resource_group), "/subscriptions/00000000-0000-0000-0000-000000000002/resourcegroups/rg-dns-b")
    error_message = "external-dns gets Reader on each distinct zone resource group"
  }
}

# The endpoints come from the mock defaults in tests/mocks.
run "issuer_flows_into_the_api_server_and_the_publish_script" {
  command = apply
  assert {
    condition     = output.oidc_issuer_url == "https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/" && azurerm_federated_identity_credential.workload["external_dns"].issuer == "https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/"
    error_message = "the issuer is the account's web endpoint and the federated credentials trust it"
  }
  assert {
    condition     = contains(output.server_config_resolved["kube-apiserver-arg"], "service-account-issuer=https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/") && contains(output.server_config_resolved["kube-apiserver-arg"], "service-account-jwks-uri=https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/openid/v1/jwks")
    error_message = "the API server issues tokens for that issuer and points at the hosted JWKS"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "https://acmeplatformdevoidc.blob.core.usgovcloudapi.net/$web") && strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "openid/v1/jwks")
    error_message = "servers publish the documents into the $web container"
  }
}
