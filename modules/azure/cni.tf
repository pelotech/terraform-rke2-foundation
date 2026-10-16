locals {
  # What each CNI choice changes. cilium and kube-ovn are installed by cni-bootstrap after this module.
  cni_profiles = {
    cilium = {
      rke2_cni               = "none"
      disable_kube_proxy     = true
      cni_node_pool          = null
      selinux_container_dirs = []
      kernel_modules         = []
    }
    "kube-ovn" = {
      rke2_cni           = "none"
      disable_kube_proxy = false
      # The chart defaults for its state, log and run directories; its pods run as container_t, not privileged.
      selinux_container_dirs = ["/etc/origin", "/opt/ovs-config", "/var/log/kube-ovn", "/var/log/ovn", "/var/log/openvswitch", "/run/openvswitch", "/run/ovn"]
      # The tunnel and the ipsets kube-ovn-cni manages; SELinux keeps container_t from loading modules itself.
      kernel_modules = ["openvswitch", "geneve", "ip_set", "ip_set_hash_ip", "ip_set_hash_net", "xt_set"]
      cni_node_pool = {
        labels = { "kube-ovn/role" = "master" }
        taints = {
          kube_ovn_control_plane = { key = "kube-ovn.io/control-plane", value = "true", effect = "NoSchedule" }
        }
      }
    }
    canal = {
      rke2_cni               = "canal"
      disable_kube_proxy     = false
      cni_node_pool          = null
      selinux_container_dirs = []
      kernel_modules         = []
    }
  }
  cni_profile = local.cni_profiles[var.cni.name]

  cni_node_pool_enabled = var.cni.node_pool != null
  cni_node_pool_labels  = try(local.cni_profile.cni_node_pool.labels, {})
  cni_node_pool_taints  = try(local.cni_profile.cni_node_pool.taints, {})

  # Without a CNI pool the poll waits for every server, which gates cni-bootstrap on the API being up.
  control_plane_selector = "node-role.kubernetes.io/control-plane=true"
  cni_node_selector      = local.cni_node_pool_enabled ? join(",", [for k, v in local.cni_node_pool_labels : "${k}=${v}"]) : local.control_plane_selector
  cni_node_size          = local.cni_node_pool_enabled ? var.cni.node_pool.node_count : var.servers.count

  dns_service_ip = coalesce(var.cluster_network.dns_service_ip, cidrhost(var.cluster_network.service_cidr, 10))
}
