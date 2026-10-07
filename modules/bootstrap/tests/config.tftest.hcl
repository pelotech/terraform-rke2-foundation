# The RKE2 config.yaml maps for servers and agent pools, and the admin kubeconfig.

run "defaults" {
  command = plan
  assert {
    condition     = output.server_config["cni"] == "none" && output.server_config["cluster-cidr"] == "10.244.0.0/16" && output.server_config["service-cidr"] == "10.96.0.0/16" && output.server_config["cluster-dns"] == "10.96.0.10"
    error_message = "network keys come from the inputs; cni none by default"
  }
  assert {
    condition     = tolist(output.server_config["tls-san"]) == tolist(["10.0.0.4"])
    error_message = "the registration address is always a SAN"
  }
  assert {
    condition     = output.server_config["secrets-encryption"] == true && output.server_config["write-kubeconfig-mode"] == "0600"
    error_message = "secrets encryption on, kubeconfig private"
  }
  assert {
    condition     = tolist(output.server_config["node-taint"]) == tolist(["CriticalAddonsOnly=true:NoSchedule"])
    error_message = "servers carry the AKS system pool taint by default"
  }
  assert {
    condition     = !contains(keys(output.server_config), "disable-kube-proxy") && !contains(keys(output.server_config), "cloud-provider-name") && !contains(keys(output.server_config), "profile") && !contains(keys(output.server_config), "disable") && !contains(keys(output.server_config), "node-label")
    error_message = "optional keys are absent, not empty"
  }
  assert {
    condition     = !contains(keys(output.server_config), "server") && !contains(keys(output.server_config), "token")
    error_message = "join settings are drop-ins written at boot, never part of config.yaml"
  }
  assert {
    condition     = length(output.agent_config) == 0
    error_message = "no agent config without agent pools"
  }
}

run "cilium_external_cis" {
  command = plan
  variables {
    disable_kube_proxy           = true
    cloud_provider_name          = "external"
    cis_profile                  = true
    disable_components           = ["rke2-metrics-server"]
    tls_sans                     = ["api.example.com", "10.0.0.4"]
    server_labels                = { role = "server" }
    kube_apiserver_args          = ["service-account-issuer=https://issuer.example/"]
    kube_controller_manager_args = ["configure-cloud-routes=false"]
    kubelet_args                 = ["max-pods=110"]
  }
  assert {
    condition     = output.server_config["disable-kube-proxy"] == true && output.server_config["cloud-provider-name"] == "external" && output.server_config["disable-cloud-controller"] == true
    error_message = "kube-proxy off; an external cloud provider also disables the RKE2 default cloud controller"
  }
  assert {
    condition     = output.server_config["profile"] == "cis" && tolist(output.server_config["disable"]) == tolist(["rke2-metrics-server"]) && output.server_config["ingress-controller"] == "none"
    error_message = "cis profile, the disable list and no packaged ingress"
  }
  assert {
    condition     = tolist(output.server_config["tls-san"]) == tolist(["10.0.0.4", "api.example.com"])
    error_message = "SANs are the registration address first, then the extras, without duplicates"
  }
  assert {
    condition     = tolist(output.server_config["node-label"]) == tolist(["role=server"])
    error_message = "labels render as key=value"
  }
  assert {
    condition     = tolist(output.server_config["kube-apiserver-arg"]) == tolist(["service-account-issuer=https://issuer.example/"]) && tolist(output.server_config["kube-controller-manager-arg"]) == tolist(["configure-cloud-routes=false"]) && tolist(output.server_config["kubelet-arg"]) == tolist(["max-pods=110"])
    error_message = "component args pass through"
  }
}

run "extra_server_config_wins" {
  command = plan
  variables {
    extra_server_config = { cni = "canal", "etcd-snapshot-retention" = 10 }
  }
  assert {
    condition     = output.server_config["cni"] == "canal" && output.server_config["etcd-snapshot-retention"] == 10
    error_message = "extra_server_config is merged last and overrides module keys"
  }
}

run "schedulable_servers_have_no_taint" {
  command = plan
  variables {
    server_taints = []
  }
  assert {
    condition     = !contains(keys(output.server_config), "node-taint")
    error_message = "an empty taint list leaves node-taint out"
  }
}

run "agent_pools" {
  command = plan
  variables {
    cloud_provider_name = "external"
    cis_profile         = true
    kubelet_args        = ["max-pods=110"]
    extra_agent_config  = { "node-name" = "override" }
    agent_pools = {
      default = {}
      cni = {
        labels       = { "kube-ovn/role" = "master" }
        taints       = ["kube-ovn.io/control-plane=true:NoSchedule"]
        kubelet_args = ["system-reserved=cpu=200m"]
      }
    }
  }
  assert {
    condition     = output.agent_config["default"]["cloud-provider-name"] == "external" && output.agent_config["default"]["profile"] == "cis" && !contains(keys(output.agent_config["default"]), "node-label") && !contains(keys(output.agent_config["default"]), "node-taint")
    error_message = "agents get the cloud provider and profile; no empty label or taint keys"
  }
  assert {
    condition     = tolist(output.agent_config["cni"]["node-label"]) == tolist(["kube-ovn/role=master"]) && tolist(output.agent_config["cni"]["node-taint"]) == tolist(["kube-ovn.io/control-plane=true:NoSchedule"])
    error_message = "pool labels and taints render into the pool's config"
  }
  assert {
    condition     = tolist(output.agent_config["cni"]["kubelet-arg"]) == tolist(["max-pods=110", "system-reserved=cpu=200m"]) && tolist(output.agent_config["default"]["kubelet-arg"]) == tolist(["max-pods=110"])
    error_message = "shared kubelet args come first, then the pool's"
  }
  assert {
    condition     = output.agent_config["cni"]["node-name"] == "override"
    error_message = "extra_agent_config is merged last"
  }
}

run "kubeconfig" {
  command = apply
  assert {
    condition     = strcontains(nonsensitive(output.kubeconfig), "\"https://10.0.0.4:6443\"") && strcontains(nonsensitive(output.kubeconfig), "client-certificate-data")
    error_message = "the kubeconfig targets the registration address with the admin client certificate"
  }
}

run "kubeconfig_url_override" {
  command = apply
  variables {
    api_server_url = "https://api.example.com:6443"
  }
  assert {
    condition     = strcontains(nonsensitive(output.kubeconfig), "\"https://api.example.com:6443\"")
    error_message = "api_server_url replaces the registration address in the kubeconfig"
  }
}

run "ingress_controller_can_be_traefik" {
  command = plan
  variables {
    ingress_controller = "traefik"
  }
  assert {
    condition     = output.server_config["ingress-controller"] == "traefik"
    error_message = "ingress_controller sets the packaged ingress"
  }
}
