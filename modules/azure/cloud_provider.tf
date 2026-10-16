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

  cloud_provider_chart_oci  = startswith(coalesce(var.cloud_provider_chart_url, "-"), "oci://")
  cloud_provider_chart_host = local.cloud_provider_chart_oci ? split("/", trimprefix(var.cloud_provider_chart_url, "oci://"))[0] : null

  # The Helm job logs in to the chart registry with this Secret and trusts the registry through this ConfigMap.
  cloud_provider_chart_manifests = merge(
    local.cloud_provider_chart_oci && var.cloud_provider_chart_credential != null ? {
      "cloud-provider-chart-registry.yaml" = yamlencode({
        apiVersion = "v1"
        kind       = "Secret"
        metadata   = { name = "cloud-provider-chart-registry", namespace = "kube-system" }
        type       = "kubernetes.io/dockerconfigjson"
        stringData = { ".dockerconfigjson" = jsonencode({ auths = { (local.cloud_provider_chart_host) = {
          username = var.cloud_provider_chart_credential.username
          password = var.cloud_provider_chart_credential.password
          auth     = base64encode("${var.cloud_provider_chart_credential.username}:${var.cloud_provider_chart_credential.password}")
        } } }) }
      })
    } : {},
    local.cloud_provider_chart_oci && var.registry_ca_pem != null ? {
      "cloud-provider-chart-ca.yaml" = yamlencode({
        apiVersion = "v1"
        kind       = "ConfigMap"
        metadata   = { name = "cloud-provider-chart-ca", namespace = "kube-system" }
        data       = { "registry-ca.pem" = var.registry_ca_pem }
      })
    } : {},
  )

  # RKE2 applies these from its manifests directory; bootstrap: true runs the chart before the nodes are schedulable.
  server_manifests = merge(local.entra_access_manifests, local.cloud_provider_chart_manifests, {
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
        } : local.cloud_provider_chart_oci ? {
        chart   = var.cloud_provider_chart_url
        version = var.cloud_provider_chart_version
        } : {
        chart = var.cloud_provider_chart_url
        },
        local.cloud_provider_chart_oci && var.cloud_provider_chart_credential != null ? { dockerRegistrySecret = { name = "cloud-provider-chart-registry" } } : {},
        local.cloud_provider_chart_oci && var.registry_ca_pem != null ? { repoCAConfigMap = { name = "cloud-provider-chart-ca" } } : {},
        {
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
