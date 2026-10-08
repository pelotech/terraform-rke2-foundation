locals {
  cni_bootstrap_cni = { cilium = "cilium", "kube-ovn" = "kube-ovn-v2" }
}

provider "helm" {
  kubernetes = {
    host                   = var.endpoint
    cluster_ca_certificate = base64decode(var.ca)
    client_certificate     = base64decode(var.cert)
    client_key             = base64decode(var.key)
  }
}

module "cni" {
  source = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=v1.1.1"

  cloud                   = "azure"
  distribution            = "rke2"
  cni                     = local.cni_bootstrap_cni[var.cni]
  cluster_endpoint        = var.endpoint
  cluster_ca_certificate  = var.ca
  client_certificate      = var.cert
  client_key              = var.key
  k8s_service_host        = "127.0.0.1"
  k8s_service_port        = "6443"
  service_cidr            = "10.96.0.0/16"
  pod_cidr                = "10.244.0.0/16"
  wait_for_nodes_count    = var.cni_node_size
  wait_for_nodes_selector = var.cni_node_selector
}
