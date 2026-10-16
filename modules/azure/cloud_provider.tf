locals {
  # azure.json for cloud-provider-azure. No credentials: the controllers use the server identity through IMDS.
  # The legacy path merges its secret last, so cloud_config_public can be an output.
  cloud_config_public = merge({
    cloud                       = local.azure_cloud.environment
    tenantId                    = data.azurerm_client_config.current.tenant_id
    subscriptionId              = data.azurerm_client_config.current.subscription_id
    resourceGroup               = local.node_resource_group_name
    location                    = var.location
    vmType                      = "vmss"
    vnetName                    = local.vnet_name
    vnetResourceGroup           = local.vnet_resource_group_name
    subnetName                  = local.node_subnet_name
    securityGroupName           = local.node_security_group_name
    securityGroupResourceGroup  = local.node_security_group_resource_group_name
    loadBalancerSku             = "standard"
    useManagedIdentityExtension = local.managed_identities
    useInstanceMetadata         = true
    excludeMasterFromStandardLB = true
  }, local.managed_identities ? { userAssignedIdentityID = azurerm_user_assigned_identity.server[0].client_id } : local.legacy_cloud_config_public)
  cloud_config = merge(local.cloud_config_public, local.legacy_cloud_config_secret)

  # The controller minor must follow Kubernetes even when the chart lags it.
  cloud_provider_image = var.cloud_provider_image_tag == null ? {} : { imageTag = var.cloud_provider_image_tag }

  cloud_provider_tolerations = [
    { key = "CriticalAddonsOnly", operator = "Exists" },
    { key = "node-role.kubernetes.io/control-plane", operator = "Exists", effect = "NoSchedule" },
    { key = "node-role.kubernetes.io/etcd", operator = "Exists", effect = "NoExecute" },
    { key = "node.cloudprovider.kubernetes.io/uninitialized", operator = "Exists", effect = "NoSchedule" },
  ]

  # RKE2 applies these from its manifests directory; bootstrap: true runs the chart before the nodes are schedulable.
  server_manifests = merge(local.entra_access_manifests, {
    "azure-cloud-config.yaml" = yamlencode({
      apiVersion = "v1"
      kind       = "Secret"
      metadata   = { name = "azure-cloud-config", namespace = "kube-system" }
      type       = "Opaque"
      stringData = { "cloud-config" = jsonencode(local.cloud_config) }
    })
    "cloud-provider-azure.yaml" = yamlencode({
      apiVersion = "helm.cattle.io/v1"
      kind       = "HelmChart"
      metadata   = { name = "cloud-provider-azure", namespace = "kube-system" }
      spec = merge(var.cloud_provider_chart_url == null ? {
        chart   = "cloud-provider-azure"
        repo    = "https://raw.githubusercontent.com/kubernetes-sigs/cloud-provider-azure/master/helm/repo"
        version = var.cloud_provider_chart_version
        } : startswith(var.cloud_provider_chart_url, "https://%%{KUBERNETES_API}%/static/") ? {
        # The static endpoint needs authentication the Helm job lacks; bootstrap.sh embeds the baked file instead.
        chartContent = "__CHART_CONTENT_FROM:/var/lib/rancher/rke2/server/static/${trimprefix(var.cloud_provider_chart_url, "https://%%{KUBERNETES_API}%/static/")}__"
        } : {
        chart = var.cloud_provider_chart_url
        }, {
        targetNamespace = "kube-system"
        bootstrap       = true
        valuesContent = yamlencode({
          infra = { clusterName = var.name }
          cloudControllerManager = merge({
            # The chart always passes --cloud-config; empty plus dynamic reloading makes the controller read the Secret.
            cloudConfig            = ""
            enableDynamicReloading = "true"
            cloudConfigSecretName  = "azure-cloud-config"
            configureCloudRoutes   = "false"
            allocateNodeCidrs      = "false"
            clusterCIDR            = var.cluster_network.pod_cidr
            nodeSelector           = { "node-role.kubernetes.io/control-plane" = "true" }
            tolerations            = local.cloud_provider_tolerations
          }, local.cloud_provider_image)
          cloudNodeManager = merge({
            tolerations = [{ operator = "Exists" }]
          }, local.cloud_provider_image)
        })
      })
    })
  })
}
