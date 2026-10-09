mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "gallery_version_replaces_marketplace_for_every_node" {
  command = plan
  variables {
    image = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/images/providers/Microsoft.Compute/galleries/rke2/images/rhel102/versions/1.37.1"
    }
    cni = "kube-ovn"
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

run "baked_chart_uses_node_static_endpoint" {
  command = apply
  variables {
    cloud_provider_chart_url = "https://%%{KUBERNETES_API}%/static/charts/cloud-provider-azure-1.36.0.tgz"
  }
  assert {
    condition = (
      yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.chart == "https://%%{KUBERNETES_API}%/static/charts/cloud-provider-azure-1.36.0.tgz" &&
      !contains(keys(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec), "repo") &&
      !contains(keys(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec), "version")
    )
    error_message = "A baked chart URL must replace the upstream repository without conflicting chart selectors."
  }
}
