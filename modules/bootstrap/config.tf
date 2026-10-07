locals {
  # Keys every node sets. A null value leaves the key out of config.yaml. Empty lists become null here, not in the
  # filter: tls-san carries values unknown at plan, and a filter that measures them would make the whole map unknown.
  node_common_config = {
    "cloud-provider-name" = var.cloud_provider_name
    "profile"             = var.cis_profile ? "cis" : null
  }

  server_config_all = merge(local.node_common_config, {
    "tls-san"                     = distinct(concat([var.registration_address], var.tls_sans))
    "cluster-cidr"                = var.pod_cidr
    "service-cidr"                = var.service_cidr
    "cluster-dns"                 = var.cluster_dns
    "cni"                         = var.cni
    "ingress-controller"          = var.ingress_controller
    "write-kubeconfig-mode"       = "0600"
    "secrets-encryption"          = var.secrets_encryption
    "disable-kube-proxy"          = var.disable_kube_proxy ? true : null
    "disable-cloud-controller"    = var.cloud_provider_name == null ? null : true
    "disable"                     = length(var.disable_components) > 0 ? var.disable_components : null
    "node-label"                  = length(var.server_labels) > 0 ? [for k, v in var.server_labels : "${k}=${v}"] : null
    "node-taint"                  = length(var.server_taints) > 0 ? var.server_taints : null
    "kube-apiserver-arg"          = length(var.kube_apiserver_args) > 0 ? var.kube_apiserver_args : null
    "kube-controller-manager-arg" = length(var.kube_controller_manager_args) > 0 ? var.kube_controller_manager_args : null
    "kubelet-arg"                 = length(var.kubelet_args) > 0 ? var.kubelet_args : null
  })
  server_config = merge({ for k, v in local.server_config_all : k => v if v != null }, var.extra_server_config)

  agent_config = {
    for pool, cfg in var.agent_pools : pool => merge(
      { for k, v in merge(local.node_common_config, {
        "node-label"  = length(cfg.labels) > 0 ? [for lk, lv in cfg.labels : "${lk}=${lv}"] : null
        "node-taint"  = length(cfg.taints) > 0 ? cfg.taints : null
        "kubelet-arg" = length(concat(var.kubelet_args, cfg.kubelet_args)) > 0 ? concat(var.kubelet_args, cfg.kubelet_args) : null
      }) : k => v if v != null },
      var.extra_agent_config,
    )
  }

  api_server_url = coalesce(var.api_server_url, "https://${var.registration_address}:6443")
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.name
      cluster = {
        server                       = local.api_server_url
        "certificate-authority-data" = base64encode(tls_self_signed_cert.ca["server_ca"].cert_pem)
      }
    }]
    users = [{
      name = "${var.name}-admin"
      user = {
        "client-certificate-data" = base64encode(tls_locally_signed_cert.admin.cert_pem)
        "client-key-data"         = base64encode(tls_private_key.admin.private_key_pem)
      }
    }]
    contexts          = [{ name = var.name, context = { cluster = var.name, user = "${var.name}-admin" } }]
    "current-context" = var.name
  })
}
