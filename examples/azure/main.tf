provider "azurerm" {
  environment = var.azure_cloud
  features {}
}

locals {
  cni_bootstrap_cni = { cilium = "cilium", "kube-ovn" = "kube-ovn-v2" }
}

module "stack" {
  source = "../../modules/azure"

  name          = var.name
  location      = var.location
  azure_cloud   = var.azure_cloud
  tags          = var.tags
  cni           = var.cni
  servers       = { vm_size = var.server_vm_size }
  cni_node_pool = { vm_size = var.cni_vm_size }
  agent_pools = {
    general = { vm_size = var.agent_vm_size, node_count = 2, min_count = 2, max_count = 5 }
  }
  cluster_endpoint_authorized_ip_ranges = var.authorized_ip_ranges
  key_vault                             = { admin_object_ids = var.key_vault_admin_object_ids }
}

provider "helm" {
  kubernetes = {
    host                   = module.stack.cluster_endpoint
    cluster_ca_certificate = base64decode(module.stack.cluster_ca_certificate)
    client_certificate     = base64decode(module.stack.admin_client_certificate)
    client_key             = base64decode(module.stack.admin_client_key)
  }
}

module "cni" {
  source = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=v1.1.1"

  create                  = var.cni != "canal"
  cloud                   = module.stack.cloud
  distribution            = module.stack.distribution
  cni                     = lookup(local.cni_bootstrap_cni, var.cni, "cilium")
  cluster_endpoint        = module.stack.cluster_endpoint
  cluster_ca_certificate  = module.stack.cluster_ca_certificate
  client_certificate      = module.stack.admin_client_certificate
  client_key              = module.stack.admin_client_key
  k8s_service_host        = module.stack.cluster_api_host
  k8s_service_port        = module.stack.cluster_api_port
  service_cidr            = module.stack.cluster_service_cidr
  pod_cidr                = module.stack.cluster_pod_cidr
  wait_for_nodes_count    = module.stack.cni_node_size
  wait_for_nodes_selector = module.stack.cni_node_selector
}

# The GitOps layer installs this in a real cluster; here it exercises the cloud config and the
# server identity's Contributor grant on the node resource group through a PVC.
resource "helm_release" "disk_csi" {
  count      = var.install_disk_csi ? 1 : 0
  name       = "azuredisk-csi-driver"
  repository = "https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/charts"
  chart      = "azuredisk-csi-driver"
  version    = var.disk_csi_chart_version
  namespace  = "kube-system"
  timeout    = 600

  set = [
    { name = "controller.cloudConfigSecretName", value = "azure-cloud-config" },
    { name = "controller.cloudConfigSecretNamespace", value = "kube-system" },
    { name = "node.cloudConfigSecretName", value = "azure-cloud-config" },
    { name = "node.cloudConfigSecretNamespace", value = "kube-system" },
    { name = "controller.runOnControlPlane", value = "true" },
    { name = "controller.replicas", value = "1" },
  ]

  depends_on = [module.cni]
}
