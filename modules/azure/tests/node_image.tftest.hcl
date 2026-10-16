mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "gallery_version_replaces_marketplace_for_every_node" {
  command = plan
  variables {
    image = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/images/providers/Microsoft.Compute/galleries/rke2/images/rhel102/versions/1.37.1"
    }
    cni = { name = "kube-ovn", node_pool = { vm_size = "Standard_D4s_v5" } }
  }
  assert {
    condition = alltrue([
      for server in azurerm_linux_virtual_machine.server :
      server.source_image_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/images/providers/Microsoft.Compute/galleries/rke2/images/rhel102/versions/1.37.1" && length(server.source_image_reference) == 0
    ])
    error_message = "Servers must use the supplied gallery version without a Marketplace reference."
  }
  assert {
    condition = alltrue([
      for pool in azurerm_linux_virtual_machine_scale_set.agent :
      pool.source_image_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/images/providers/Microsoft.Compute/galleries/rke2/images/rhel102/versions/1.37.1" && length(pool.source_image_reference) == 0
    ])
    error_message = "Every scale set, including the CNI pool, must use the same gallery version."
  }
}

run "gallery_latest_is_rejected" {
  command = plan
  variables {
    image = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/images/providers/Microsoft.Compute/galleries/rke2/images/rhel102/versions/latest"
    }
  }
  expect_failures = [var.image]
}

run "offline_inputs_reach_all_node_roles" {
  command = apply
  variables {
    install_artifact_path = "/opt/rke2/artifacts"
  }
  assert {
    condition = alltrue(concat(
      [for server in azurerm_linux_virtual_machine.server : strcontains(base64decode(server.custom_data), "INSTALL_ARTIFACT_PATH=/opt/rke2/artifacts")],
      [for pool in azurerm_linux_virtual_machine_scale_set.agent : strcontains(base64decode(pool.custom_data), "INSTALL_ARTIFACT_PATH=/opt/rke2/artifacts")],
    ))
    error_message = "The offline installation path must reach every server and agent cloud-init."
  }
}

run "oci_chart_logs_in_and_trusts_the_registry" {
  command = apply
  variables {
    cloud_provider_chart_url        = "oci://registry.example.mil/group/project/charts/cloud-provider-azure"
    cloud_provider_chart_credential = { username = "puller", password = "sentinel-pull-secret" }
    registry_ca_pem                 = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
  }
  assert {
    condition = (
      yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.chart == "oci://registry.example.mil/group/project/charts/cloud-provider-azure" &&
      yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.version == "1.36.0" &&
      yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.dockerRegistrySecret.name == "cloud-provider-chart-registry" &&
      yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.repoCAConfigMap.name == "cloud-provider-chart-ca" &&
      !contains(keys(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec), "repo")
    )
    error_message = "An oci:// chart is installed by version from the registry, with the pull secret and the CA ConfigMap."
  }
  assert {
    condition = (
      contains(keys(jsondecode(yamldecode(output.server_manifests_resolved["cloud-provider-chart-registry.yaml"]).stringData[".dockerconfigjson"]).auths), "registry.example.mil") &&
      yamldecode(output.server_manifests_resolved["cloud-provider-chart-ca.yaml"]).data["registry-ca.pem"] == var.registry_ca_pem
    )
    error_message = "The Secret logs in to the registry host of the chart path and the ConfigMap carries registry_ca_pem."
  }
}

run "oci_chart_without_credential_pulls_anonymously" {
  command = plan
  variables {
    cloud_provider_chart_url = "oci://registry.example.mil/group/project/charts/cloud-provider-azure"
  }
  assert {
    condition     = !contains(keys(output.server_manifests_resolved), "cloud-provider-chart-registry.yaml")
    error_message = "no credential, no registry Secret"
  }
}

run "chart_credential_needs_an_oci_url" {
  command = plan
  variables {
    cloud_provider_chart_url        = "https://charts.example.mil/cloud-provider-azure-1.36.0.tgz"
    cloud_provider_chart_credential = { username = "puller", password = "sentinel-pull-secret" }
  }
  expect_failures = [var.cloud_provider_chart_credential]
}
