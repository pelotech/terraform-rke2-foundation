# cloud-provider-azure: the cloud config and the manifests servers write before RKE2 starts.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "cloud_config_for_azure_government" {
  command = plan
  assert {
    condition     = output.cloud_config_resolved.cloud == "AzureUSGovernmentCloud" && output.cloud_config_resolved.tenantId == "00000000-0000-0000-0000-000000000001" && output.cloud_config_resolved.subscriptionId == "00000000-0000-0000-0000-000000000002"
    error_message = "the cloud name follows azure_cloud; tenant and subscription come from the provider"
  }
  assert {
    condition     = output.cloud_config_resolved.resourceGroup == "rg-platformdev-nodes" && output.cloud_config_resolved.securityGroupName == "nsg-platformdev-nodes" && output.cloud_config_resolved.securityGroupResourceGroup == "rg-platformdev-nodes"
    error_message = "the cloud provider works in the node group and the module's security group"
  }
  assert {
    condition     = output.cloud_config_resolved.vnetName == "vnet-platformdev" && output.cloud_config_resolved.vnetResourceGroup == "rg-platformdev" && output.cloud_config_resolved.subnetName == "snet-platformdev-nodes"
    error_message = "the module's VNet and node subnet"
  }
  assert {
    condition     = output.cloud_config_resolved.vmType == "vmss" && output.cloud_config_resolved.loadBalancerSku == "standard" && output.cloud_config_resolved.useManagedIdentityExtension == true && output.cloud_config_resolved.useInstanceMetadata == true && output.cloud_config_resolved.excludeMasterFromStandardLB == true
    error_message = "scale set mode, standard load balancers, managed identity through IMDS, servers out of service load balancers"
  }
  assert {
    condition     = !contains(keys(output.cloud_config_resolved), "aadClientId") && !contains(keys(output.cloud_config_resolved), "aadClientSecret")
    error_message = "no credentials in the cloud config"
  }
}

run "cloud_config_for_public_cloud" {
  command = plan
  variables {
    azure_cloud = "public"
  }
  assert {
    condition     = output.cloud_config_resolved.cloud == "AzurePublicCloud"
    error_message = "public maps to AzurePublicCloud"
  }
}

run "server_manifests" {
  command = plan
  assert {
    condition     = sort(keys(output.server_manifests_resolved)) == tolist(["azure-cloud-config.yaml", "cloud-provider-azure.yaml"])
    error_message = "a Secret with the cloud config and the cloud-provider-azure HelmChart"
  }
  assert {
    condition     = output.server_config_resolved["cloud-provider-name"] == "external" && output.server_config_resolved["disable-cloud-controller"] == true && tolist(output.server_config_resolved["kube-controller-manager-arg"]) == tolist(["configure-cloud-routes=false"])
    error_message = "RKE2 defers to the external cloud provider"
  }
}

# The manifests embed the server identity's client id, so their text is only known after apply.
run "server_manifest_contents" {
  command = apply
  assert {
    condition     = strcontains(output.server_manifests_resolved["cloud-provider-azure.yaml"], "\"version\": \"1.36.0\"") && strcontains(output.server_manifests_resolved["cloud-provider-azure.yaml"], "\"bootstrap\": true") && strcontains(output.server_manifests_resolved["cloud-provider-azure.yaml"], "cloudConfigSecretName")
    error_message = "the chart is pinned, bootstraps early and reads the cloud config secret"
  }
  assert {
    condition     = yamldecode(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.valuesContent).cloudControllerManager.cloudConfig == "" && yamldecode(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.valuesContent).cloudControllerManager.enableDynamicReloading == "true"
    error_message = "cloudConfig must be empty and dynamic reloading on, or the controller opens /etc/kubernetes/azure.json and never reads the Secret"
  }
  assert {
    condition     = yamldecode(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.valuesContent).cloudControllerManager.imageTag == "v1.37.0" && yamldecode(yamldecode(output.server_manifests_resolved["cloud-provider-azure.yaml"]).spec.valuesContent).cloudNodeManager.imageTag == "v1.37.0"
    error_message = "by default both images follow the Kubernetes minor through cloud_provider_image_tag"
  }
  assert {
    condition     = strcontains(output.server_manifests_resolved["azure-cloud-config.yaml"], "\"name\": \"azure-cloud-config\"") && strcontains(output.server_manifests_resolved["azure-cloud-config.yaml"], "AzureUSGovernmentCloud")
    error_message = "the secret is named azure-cloud-config in kube-system and carries the cloud config"
  }
}

run "chart_image_tag_when_null" {
  command = apply
  variables {
    cloud_provider_image_tag = null
  }
  assert {
    condition     = !strcontains(output.server_manifests_resolved["cloud-provider-azure.yaml"], "imageTag")
    error_message = "a null tag leaves the chart's own image tag in place"
  }
}
