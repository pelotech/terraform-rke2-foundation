locals {
  # What each CNI choice changes. cilium and kube-ovn are installed by cni-bootstrap after this module.
  cni_profiles = {
    cilium = {
      rke2_cni           = "none"
      disable_kube_proxy = true
      cni_node_pool      = null
    }
    "kube-ovn" = {
      rke2_cni           = "none"
      disable_kube_proxy = false
      cni_node_pool = {
        labels = { "kube-ovn/role" = "master" }
        taints = {
          kube_ovn_control_plane = { key = "kube-ovn.io/control-plane", value = "true", effect = "NoSchedule" }
        }
      }
    }
    canal = {
      rke2_cni           = "canal"
      disable_kube_proxy = false
      cni_node_pool      = null
    }
  }
  cni_profile = local.cni_profiles[var.cni]

  cni_node_pool_enabled = local.cni_profile.cni_node_pool != null && var.cni_node_pool.enabled
  cni_node_pool_labels  = try(local.cni_profile.cni_node_pool.labels, {})
  cni_node_pool_taints  = try(local.cni_profile.cni_node_pool.taints, {})

  # Without a CNI pool the poll waits for every server, which gates cni-bootstrap on the API being up.
  control_plane_selector = "node-role.kubernetes.io/control-plane=true"
  cni_node_selector      = local.cni_node_pool_enabled ? join(",", [for k, v in local.cni_node_pool_labels : "${k}=${v}"]) : local.control_plane_selector
  cni_node_size          = local.cni_node_pool_enabled ? var.cni_node_pool.node_count : var.servers.count

  dns_service_ip = coalesce(var.dns_service_ip, cidrhost(var.service_cidr, 10))
}
