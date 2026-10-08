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
      "oidc-username-claim=oid",
      "oidc-groups-claim=groups",
      "oidc-username-prefix=-",
    ])
    error_message = "the Gov v2 issuer for the tenant, the app as audience, default claims, no username prefix"
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

run "entra_subjects_get_bindings_and_a_kubeconfig" {
  command = apply
  variables {
    entra_oidc = {
      enabled                = true
      client_id              = "22222222-2222-2222-2222-222222222222"
      username_prefix        = "entra:"
      admin_group_object_ids = ["33333333-3333-3333-3333-333333333333"]
      admin_object_ids       = ["44444444-4444-4444-4444-444444444444"]
      reader_object_ids      = ["55555555-5555-5555-5555-555555555555"]
    }
  }
  assert {
    condition     = output.server_config_resolved["kube-apiserver-arg"] != null && contains(output.server_config_resolved["kube-apiserver-arg"], "oidc-username-claim=oid")
    error_message = "oid is the username claim by default, so service principal tokens carry one too"
  }
  assert {
    condition     = strcontains(output.server_manifests_resolved["entra-access.yaml"], "entra-cluster-admins") && strcontains(output.server_manifests_resolved["entra-access.yaml"], "\"name\": \"33333333-3333-3333-3333-333333333333\"") && strcontains(output.server_manifests_resolved["entra-access.yaml"], "\"name\": \"entra:44444444-4444-4444-4444-444444444444\"")
    error_message = "the admin group is a Group subject by id; the admin identity a User subject with the prefix"
  }
  assert {
    condition     = strcontains(output.server_manifests_resolved["entra-access.yaml"], "entra-readers-helm-releases") && strcontains(output.server_manifests_resolved["entra-access.yaml"], "\"name\": \"entra:55555555-5555-5555-5555-555555555555\"")
    error_message = "readers get view plus the kube-system secrets Helm releases live in"
  }
  assert {
    condition     = yamldecode(output.kubeconfig_entra).users[0].user.exec.command == "kubelogin" && contains(yamldecode(output.kubeconfig_entra).users[0].user.exec.args, "22222222-2222-2222-2222-222222222222") && !strcontains(output.kubeconfig_entra, "client-key-data")
    error_message = "the Entra kubeconfig carries the kubelogin exec block and no secret"
  }
}

run "entra_object_ids_without_a_prefix" {
  command = apply
  variables {
    entra_oidc = {
      enabled           = true
      client_id         = "22222222-2222-2222-2222-222222222222"
      admin_object_ids  = ["44444444-4444-4444-4444-444444444444"]
      reader_object_ids = ["55555555-5555-5555-5555-555555555555"]
    }
  }
  assert {
    condition     = contains(output.server_config_resolved["kube-apiserver-arg"], "oidc-username-prefix=-") && strcontains(output.server_manifests_resolved["entra-access.yaml"], "\"name\": \"44444444-4444-4444-4444-444444444444\"") && strcontains(output.server_manifests_resolved["entra-access.yaml"], "\"name\": \"55555555-5555-5555-5555-555555555555\"")
    error_message = "a null prefix renders, tells the API server to add none, and binds the bare object ids"
  }
}

run "entra_off_adds_no_manifest" {
  command = apply
  assert {
    condition     = !contains(keys(output.server_manifests_resolved), "entra-access.yaml") && output.kubeconfig_entra == null
    error_message = "without entra_oidc there is no binding manifest and no Entra kubeconfig"
  }
}
