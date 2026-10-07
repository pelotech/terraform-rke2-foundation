locals {
  # The same profile values modules/azure derives from its cni input.
  profiles = {
    cilium = {
      disable_kube_proxy = true
      cni_pool           = {}
    }
    "kube-ovn" = {
      disable_kube_proxy = false
      cni_pool = {
        cni = { labels = { "kube-ovn/role" = "master" }, taints = ["kube-ovn.io/control-plane=true:NoSchedule"] }
      }
    }
  }
  profile = local.profiles[var.cni]
}

module "bootstrap" {
  source = "../../modules/bootstrap"

  name                 = "local"
  rke2_version         = var.rke2_version
  registration_address = var.registration_address
  service_cidr         = "10.96.0.0/16"
  pod_cidr             = "10.244.0.0/16"
  cluster_dns          = "10.96.0.10"
  cni                  = "none"
  disable_kube_proxy   = local.profile.disable_kube_proxy
  disable_components   = ["rke2-snapshot-controller", "rke2-snapshot-controller-crd", "rke2-snapshot-validation-webhook"]
  agent_pools          = merge({ general = { labels = { pool = "general" } } }, local.profile.cni_pool)
  fetch_secrets_scripts = {
    server = file("${path.module}/fetch-stub.sh")
    agent  = file("${path.module}/fetch-stub.sh")
  }
  put_snapshot_script = file("${path.module}/put-snapshot-stub.sh")
}
