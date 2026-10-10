locals {
  # azure.json for cloud-provider-azure. No credentials: the controllers use the server identity through IMDS.
  cloud_config = {
    cloud                       = local.azure_cloud.environment
    tenantId                    = data.azurerm_client_config.current.tenant_id
    subscriptionId              = data.azurerm_client_config.current.subscription_id
    resourceGroup               = azurerm_resource_group.nodes.name
    location                    = var.location
    vmType                      = "vmss"
    vnetName                    = local.vnet_name
    vnetResourceGroup           = local.vnet_resource_group_name
    subnetName                  = local.node_subnet_name
    securityGroupName           = azurerm_network_security_group.nodes.name
    securityGroupResourceGroup  = azurerm_resource_group.nodes.name
    loadBalancerSku             = "standard"
    useManagedIdentityExtension = true
    userAssignedIdentityID      = azurerm_user_assigned_identity.server.client_id
    useInstanceMetadata         = true
    excludeMasterFromStandardLB = true
  }

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
            clusterCIDR            = var.pod_cidr
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
