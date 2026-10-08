# The stack-to-CNI contract: every output cni-bootstrap and the helm provider consume.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "contract_values_known_at_plan" {
  command = plan
  assert {
    condition     = output.cloud == "azure" && output.distribution == "rke2"
    error_message = "cloud and distribution"
  }
  assert {
    condition     = output.cluster_api_host == "127.0.0.1" && output.cluster_api_port == 6443
    error_message = "Cilium talks to the RKE2 agent load balancer on every node"
  }
  assert {
    condition     = output.cluster_service_cidr == "10.96.0.0/16" && output.cluster_pod_cidr == "10.244.0.0/16" && output.dns_service_ip_resolved == "10.96.0.10"
    error_message = "cidrs and dns ip"
  }
  assert {
    condition     = output.kube_exec == null && output.cluster_name == "platformdev" && output.cluster_version == "v1.37.1+rke2r1"
    error_message = "no exec plugin without entra_oidc; name and version pass through"
  }
  assert {
    condition     = output.resource_group_name == "rg-platformdev" && output.node_resource_group_name == "rg-platformdev-nodes" && azurerm_resource_group.this[0].location == "usgovvirginia" && output.region == "usgovvirginia"
    error_message = "resource groups default to rg-<name> and rg-<name>-nodes in var.location"
  }
  assert {
    condition     = output.subscription_id == "00000000-0000-0000-0000-000000000002" && output.tenant_id == "00000000-0000-0000-0000-000000000001"
    error_message = "subscription_id and tenant_id come from the provider's client config"
  }
  assert {
    condition     = output.api_private_ip == "10.0.3.254" && output.server_config_resolved["cni"] == "none"
    error_message = "the internal API address and the RKE2 cni value"
  }
}

run "existing_resource_group_is_not_created" {
  command = plan
  variables {
    create_resource_group = false
    resource_group_name   = "rg-shared"
  }
  assert {
    condition     = length(azurerm_resource_group.this) == 0 && output.resource_group_name == "rg-shared" && azurerm_key_vault.this.resource_group_name == "rg-shared"
    error_message = "create_resource_group = false must reuse the named group"
  }
}

run "every_contract_output_is_populated" {
  command = apply

  override_resource {
    target = azurerm_public_ip.api[0]
    values = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platformdev/providers/Microsoft.Network/publicIPAddresses/pip-platformdev-api"
      fqdn       = "platformdev-abcd1234.usgovvirginia.cloudapp.usgovcloudapi.net"
      ip_address = "20.140.1.2"
    }
  }

  assert {
    condition     = output.cluster_endpoint == "https://platformdev-abcd1234.usgovvirginia.cloudapp.usgovcloudapi.net:6443" && output.api_public_fqdn == "platformdev-abcd1234.usgovvirginia.cloudapp.usgovcloudapi.net" && output.api_public_ip == "20.140.1.2"
    error_message = "cluster_endpoint is the public FQDN on 6443"
  }
  assert {
    condition     = strcontains(base64decode(output.cluster_ca_certificate), "BEGIN CERTIFICATE") && strcontains(base64decode(output.admin_client_certificate), "BEGIN CERTIFICATE") && strcontains(base64decode(output.admin_client_key), "PRIVATE KEY")
    error_message = "the CA and the admin credential are base64 PEM, known before any VM exists"
  }
  assert {
    condition     = strcontains(nonsensitive(output.kubeconfig), "\"https://platformdev-abcd1234.usgovvirginia.cloudapp.usgovcloudapi.net:6443\"")
    error_message = "the kubeconfig targets the public endpoint"
  }
  assert {
    condition     = output.cni_node_size == 3 && output.cni_node_selector == "node-role.kubernetes.io/control-plane=true"
    error_message = "cni node contract for cilium"
  }
  assert {
    condition     = contains(output.server_config_resolved["tls-san"], "10.0.3.254") && contains(output.server_config_resolved["tls-san"], "platformdev-abcd1234.usgovvirginia.cloudapp.usgovcloudapi.net")
    error_message = "the API certificate covers the internal address and the public FQDN"
  }
  assert {
    condition     = output.oidc_issuer_url == "https://acmeplatformdevoidc.z1.web.core.usgovcloudapi.net/" && output.oidc_storage_account_id == azurerm_storage_account.oidc[0].id && output.external_dns_client_id != null && output.cert_manager_client_id != null
    error_message = "issuer, its storage account id and the GitOps layer's client ids are populated by default"
  }
  assert {
    condition     = output.key_vault_name == "kv-platformdev" && output.key_vault_id != null && output.server_identity_client_id != null && output.agent_identity_client_id != null
    error_message = "vault and identity outputs"
  }
  assert {
    condition     = length(output.server_vm_ids) == 3 && sort(keys(output.agent_scale_set_ids)) == tolist(["general"]) && output.node_security_group_id != null && output.vnet_id != null && output.node_subnet_id != null && length(output.nat_gateway_public_ips) == 1
    error_message = "node and network outputs"
  }
  assert {
    condition     = output.blob_csi_storage_account_id == null && output.database_subnet_id == null
    error_message = "optional resources report null when absent"
  }
}
