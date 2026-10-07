# Entra ID as the API server's OIDC provider, and the kube_exec block it enables.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

# Without workload identity the API server args hold only the OIDC flags under test.
variables {
  workload_identity = { enabled = false }
}

run "entra_oidc_in_azure_government" {
  command = plan
  variables {
    entra_oidc = { enabled = true, client_id = "22222222-2222-2222-2222-222222222222" }
  }
  assert {
    condition = toset(output.server_config_resolved["kube-apiserver-arg"]) == toset([
      "oidc-issuer-url=https://login.microsoftonline.us/00000000-0000-0000-0000-000000000001/v2.0",
      "oidc-client-id=22222222-2222-2222-2222-222222222222",
      "oidc-username-claim=preferred_username",
      "oidc-groups-claim=groups",
    ])
    error_message = "the Gov v2 issuer for the tenant, the app as audience, default claims"
  }
  assert {
    condition     = output.kube_exec.command == "kubelogin" && output.kube_exec.args == ["get-token", "--login", "azurecli", "--server-id", "22222222-2222-2222-2222-222222222222", "--environment", "AzureUSGovernmentCloud"]
    error_message = "kube_exec is the kubelogin invocation for that app in Azure Government"
  }
}

run "entra_oidc_overrides_in_public_cloud" {
  command = plan
  variables {
    azure_cloud          = "public"
    kube_exec_login_mode = "spn"
    entra_oidc = {
      enabled         = true
      client_id       = "22222222-2222-2222-2222-222222222222"
      issuer_url      = "https://sts.windows.net/00000000-0000-0000-0000-000000000001/"
      username_claim  = "upn"
      username_prefix = "entra:"
    }
  }
  assert {
    condition     = contains(output.server_config_resolved["kube-apiserver-arg"], "oidc-issuer-url=https://sts.windows.net/00000000-0000-0000-0000-000000000001/") && contains(output.server_config_resolved["kube-apiserver-arg"], "oidc-username-claim=upn") && contains(output.server_config_resolved["kube-apiserver-arg"], "oidc-username-prefix=entra:")
    error_message = "issuer, claim and prefix overrides pass through"
  }
  assert {
    condition     = output.kube_exec.args[2] == "spn" && output.kube_exec.args[6] == "AzurePublicCloud"
    error_message = "login mode and the public cloud environment"
  }
}
