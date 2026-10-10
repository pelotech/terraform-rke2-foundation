# Servers, the API load balancers, the security rule, agent pools and the CNI profiles.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "servers_defaults" {
  command = plan
  assert {
    condition     = length(azurerm_linux_virtual_machine.server) == 3 && azurerm_linux_virtual_machine.server[0].name == "platformdev-server-0" && alltrue([for s in azurerm_linux_virtual_machine.server : s.name == s.computer_name])
    error_message = "three servers whose VM name is the hostname, which the cloud provider looks nodes up by"
  }
  assert {
    condition     = [for s in azurerm_linux_virtual_machine.server : s.zone] == ["1", "2", "3"]
    error_message = "servers round-robin across the zones"
  }
  assert {
    condition     = alltrue([for s in azurerm_linux_virtual_machine.server : s.size == "Standard_D4s_v5" && s.admin_username == "rke2admin" && s.disable_password_authentication == true && s.os_disk[0].disk_size_gb == 100 && s.os_disk[0].storage_account_type == "Premium_LRS"])
    error_message = "size, admin user, no passwords, premium 100 GB disk"
  }
  assert {
    condition     = alltrue([for s in azurerm_linux_virtual_machine.server : s.source_image_reference[0].publisher == "RedHat" && s.source_image_reference[0].offer == "RHEL" && s.source_image_reference[0].sku == "10_2-gen2" && s.source_image_reference[0].version != "latest" && length(s.plan) == 0])
    error_message = "RHEL 10.2 generation 2 by default, pinned to one build, without a marketplace plan"
  }
  assert {
    condition     = alltrue([for s in azurerm_linux_virtual_machine.server : s.identity[0].type == "UserAssigned" && length(s.boot_diagnostics) == 1])
    error_message = "servers run as the server identity with managed boot diagnostics"
  }
  assert {
    condition     = length(azurerm_network_interface.server) == 3 && azurerm_network_interface.server[1].name == "nic-platformdev-server-1" && length(azurerm_network_interface_security_group_association.server) == 3
    error_message = "one NIC per server, each behind the node security group"
  }
  assert {
    condition     = length(azurerm_network_interface_backend_address_pool_association.server_api) == 3 && length(azurerm_network_interface_backend_address_pool_association.server_api_public) == 3
    error_message = "every server sits behind the internal and the public API load balancer"
  }
}

run "api_load_balancers_and_security_rule" {
  command = plan
  assert {
    condition     = azurerm_lb.api.name == "lb-platformdev-api" && azurerm_lb.api.sku == "Standard" && azurerm_lb.api.frontend_ip_configuration[0].name == "api"
    error_message = "a Standard internal load balancer"
  }
  assert {
    condition     = azurerm_lb_rule.api["api"].frontend_port == 6443 && azurerm_lb_rule.api["supervisor"].frontend_port == 9345 && azurerm_lb_probe.api["supervisor"].port == 9345 && azurerm_lb_rule.api["api"].idle_timeout_in_minutes == 30
    error_message = "6443 and 9345 with their own probes and a long idle timeout for watches"
  }
  assert {
    condition     = length(azurerm_public_ip.api) == 1 && azurerm_public_ip.api[0].sku == "Standard" && azurerm_public_ip.api[0].allocation_method == "Static" && startswith(azurerm_public_ip.api[0].domain_name_label, "platformdev-") && length(azurerm_public_ip.api[0].domain_name_label) == 20
    error_message = "a static public ip with a <name>-<8 hex> DNS label"
  }
  assert {
    condition     = length(azurerm_lb.api_public) == 1 && azurerm_lb_rule.api["public_api"].frontend_port == 6443 && azurerm_lb_rule.api["public_api"].disable_outbound_snat == true && azurerm_lb_rule.api["api"].disable_outbound_snat == false
    error_message = "the public load balancer fronts 6443 only and does no outbound SNAT"
  }
  assert {
    condition     = length(azurerm_network_security_rule.api_server) == 1 && azurerm_network_security_rule.api_server[0].source_address_prefix == "Internet" && azurerm_network_security_rule.api_server[0].destination_port_range == "6443"
    error_message = "the API rule allows the internet by default"
  }
}

run "authorized_ranges_and_dns_label" {
  command = plan
  variables {
    cluster_endpoint_authorized_ip_ranges = ["203.0.113.0/24", "198.51.100.7/32"]
    cluster_endpoint_dns_label            = "platform-dev-api"
  }
  assert {
    condition     = toset(azurerm_network_security_rule.api_server[0].source_address_prefixes) == toset(["203.0.113.0/24", "198.51.100.7/32"]) && azurerm_network_security_rule.api_server[0].source_address_prefix == null
    error_message = "authorized ranges replace the Internet source"
  }
  assert {
    condition     = azurerm_public_ip.api[0].domain_name_label == "platform-dev-api"
    error_message = "the DNS label can be chosen"
  }
}

run "private_cluster_has_no_public_surface" {
  command = plan
  variables {
    cluster_endpoint_public_access = false
  }
  assert {
    condition     = length(azurerm_public_ip.api) == 0 && length(azurerm_lb.api_public) == 0 && !contains(keys(azurerm_lb_rule.api), "public_api") && length(azurerm_network_security_rule.api_server) == 0 && length(azurerm_network_interface_backend_address_pool_association.server_api_public) == 0
    error_message = "no public ip, load balancer, security rule or pool membership"
  }
  assert {
    condition     = output.cluster_endpoint == "https://10.0.3.254:6443" && output.api_public_fqdn == null
    error_message = "the endpoint is the internal address"
  }
}

run "agent_pool_defaults" {
  command = plan
  assert {
    condition     = length(azurerm_linux_virtual_machine_scale_set.agent) == 1 && azurerm_linux_virtual_machine_scale_set.agent["general"].name == "vmss-platformdev-general" && azurerm_linux_virtual_machine_scale_set.agent["general"].computer_name_prefix == "platformdev-general-"
    error_message = "one scale set per pool, named vmss-<name>-<pool>"
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["general"].instances == 1 && tolist(azurerm_linux_virtual_machine_scale_set.agent["general"].zones) == tolist(["1", "2", "3"]) && azurerm_linux_virtual_machine_scale_set.agent["general"].upgrade_mode == "Manual" && azurerm_linux_virtual_machine_scale_set.agent["general"].overprovision == false
    error_message = "initial size, zones, manual upgrades, no overprovisioning"
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["general"].identity[0].type == "UserAssigned" && azurerm_linux_virtual_machine_scale_set.agent["general"].network_interface[0].ip_configuration[0].primary == true && azurerm_linux_virtual_machine_scale_set.agent["general"].disable_password_authentication == true
    error_message = "agents run as the agent identity on one primary NIC, without passwords"
  }
  assert {
    condition     = !contains(keys(azurerm_linux_virtual_machine_scale_set.agent["general"].tags), "cluster-autoscaler-enabled")
    error_message = "no autoscaler tags without min_count and max_count"
  }
}

run "autoscaled_pool_and_image_plan" {
  command = plan
  variables {
    agent_pools = {
      general = { vm_size = "Standard_D4s_v5", node_count = 2, min_count = 1, max_count = 5, labels = { tier = "general" } }
      gpu     = { vm_size = "Standard_NC4as_T4_v3", zones = [], os_disk_type = "StandardSSD_LRS", taints = { gpu = { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" } } }
    }
    image = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-pro-jammy-fips"
      sku       = "pro-fips-22_04"
      plan      = { name = "pro-fips-22_04", product = "0001-com-ubuntu-pro-jammy-fips", publisher = "canonical" }
    }
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["general"].tags["cluster-autoscaler-enabled"] == "true" && azurerm_linux_virtual_machine_scale_set.agent["general"].tags["cluster-autoscaler-name"] == "platformdev" && azurerm_linux_virtual_machine_scale_set.agent["general"].tags["min"] == "1" && azurerm_linux_virtual_machine_scale_set.agent["general"].tags["max"] == "5" && azurerm_linux_virtual_machine_scale_set.agent["general"].tags["Owner"] == "acme"
    error_message = "min and max tag the pool for cluster-autoscaler, next to the consumer's tags"
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["gpu"].zones == null && azurerm_linux_virtual_machine_scale_set.agent["gpu"].os_disk[0].storage_account_type == "StandardSSD_LRS" && !contains(keys(azurerm_linux_virtual_machine_scale_set.agent["gpu"].tags), "min")
    error_message = "empty zones mean no zone; disk type passes through; a fixed pool has no autoscaler tags"
  }
  assert {
    condition     = azurerm_linux_virtual_machine.server[0].plan[0].product == "0001-com-ubuntu-pro-jammy-fips" && azurerm_linux_virtual_machine_scale_set.agent["gpu"].plan[0].name == "pro-fips-22_04"
    error_message = "a marketplace plan applies to servers and agents"
  }
  assert {
    condition     = tolist(output.agent_pools_resolved["gpu"].taints) == tolist(["nvidia.com/gpu=true:NoSchedule"]) && tomap(output.agent_pools_resolved["general"].labels) == tomap({ tier = "general" })
    error_message = "pool taints render as key=value:Effect for RKE2"
  }
}

run "kube_ovn_adds_the_cni_pool" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { vm_size = "Standard_D8s_v5", zones = ["2"] }
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["cni"].name == "vmss-platformdev-cni" && azurerm_linux_virtual_machine_scale_set.agent["cni"].instances == 1 && azurerm_linux_virtual_machine_scale_set.agent["cni"].sku == "Standard_D8s_v5" && tolist(azurerm_linux_virtual_machine_scale_set.agent["cni"].zones) == tolist(["2"])
    error_message = "the cni pool is a one node scale set with its own size and zones"
  }
  assert {
    condition     = tomap(output.agent_pools_resolved["cni"].labels) == tomap({ "kube-ovn/role" = "master" }) && tolist(output.agent_pools_resolved["cni"].taints) == tolist(["kube-ovn.io/control-plane=true:NoSchedule"])
    error_message = "the kube-ovn master label and taint"
  }
  assert {
    condition     = output.cni_node_size == 1 && output.cni_node_selector == "kube-ovn/role=master" && output.cni_node_pool_enabled == true
    error_message = "cni-bootstrap waits for the master node"
  }
  assert {
    condition     = output.server_config_resolved["cni"] == "none" && !contains(keys(output.server_config_resolved), "disable-kube-proxy")
    error_message = "kube-ovn keeps kube-proxy on"
  }
  assert {
    condition     = tolist(output.selinux_container_dirs_resolved) == tolist(["/etc/origin", "/opt/ovs-config", "/var/log/kube-ovn", "/var/log/ovn", "/var/log/openvswitch", "/run/openvswitch", "/run/ovn"])
    error_message = "the bootstrap labels the kube-ovn host directories for SELinux"
  }
}

run "cilium_labels_no_host_directories" {
  command = plan
  assert {
    condition     = length(output.selinux_container_dirs_resolved) == 0
    error_message = "cilium runs privileged and needs no host directory label"
  }
}

run "cni_pool_can_be_recycled" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { enabled = false }
  }
  assert {
    condition     = !contains(keys(azurerm_linux_virtual_machine_scale_set.agent), "cni") && output.cni_node_size == 3 && output.cni_node_selector == "node-role.kubernetes.io/control-plane=true"
    error_message = "enabled = false drops the pool and the poll falls back to the servers"
  }
}

run "cilium_contract_and_config" {
  command = plan
  assert {
    condition     = output.cni_node_size == 3 && output.cni_node_selector == "node-role.kubernetes.io/control-plane=true" && output.cni_node_pool_enabled == false
    error_message = "with cilium the poll waits for the three servers"
  }
  assert {
    condition     = output.server_config_resolved["cni"] == "none" && output.server_config_resolved["disable-kube-proxy"] == true && tolist(output.server_config_resolved["node-taint"]) == tolist(["CriticalAddonsOnly=true:NoSchedule", "node-role.kubernetes.io/control-plane=true:NoSchedule"])
    error_message = "cilium replaces kube-proxy; servers carry the system taint"
  }
  assert {
    condition     = tolist(output.server_config_resolved["disable"]) == tolist(["rke2-snapshot-controller", "rke2-snapshot-controller-crd", "rke2-snapshot-validation-webhook"]) && output.server_config_resolved["ingress-controller"] == "none" && output.server_config_resolved["secrets-encryption"] == true
    error_message = "no packaged ingress or snapshot controller; secrets encryption on"
  }
}

run "canal_is_bundled" {
  command = plan
  variables {
    cni = "canal"
  }
  assert {
    condition     = output.server_config_resolved["cni"] == "canal" && !contains(keys(output.server_config_resolved), "disable-kube-proxy") && output.cni_node_size == 3
    error_message = "canal is RKE2's own CNI with kube-proxy on"
  }
}

run "schedulable_servers_and_cis" {
  command = plan
  variables {
    servers     = { vm_size = "Standard_D4s_v5", count = 1, schedulable = true, labels = { role = "all" }, zones = [] }
    cis_profile = true
  }
  assert {
    condition     = length(azurerm_linux_virtual_machine.server) == 1 && azurerm_linux_virtual_machine.server[0].zone == null && !contains(keys(output.server_config_resolved), "node-taint") && tolist(output.server_config_resolved["node-label"]) == tolist(["role=all"])
    error_message = "a single schedulable server without a zone"
  }
  assert {
    condition     = output.server_config_resolved["profile"] == "cis"
    error_message = "cis_profile sets the RKE2 profile"
  }
}

run "server_cloud_init_roles" {
  command = apply
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "INIT_CANDIDATE=true") && strcontains(base64decode(azurerm_linux_virtual_machine.server[1].custom_data), "INIT_CANDIDATE=false")
    error_message = "server zero is the init candidate"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.server[1].custom_data), "REGISTRATION_ADDRESS=10.0.3.254") && strcontains(base64decode(azurerm_linux_virtual_machine.server[1].custom_data), "https://kv-platformdev.vault.usgovcloudapi.net/") && strcontains(base64decode(azurerm_linux_virtual_machine.server[1].custom_data), "https://vault.usgovcloudapi.net")
    error_message = "servers join through the internal address and fetch from the vault with the Gov audience"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.server[1].custom_data), azurerm_user_assigned_identity.server.client_id) && strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), azurerm_user_assigned_identity.agent.client_id) && !strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), azurerm_user_assigned_identity.server.client_id)
    error_message = "each role fetches with its own identity"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), "SECRETS=\"rke2-agent-token=agent-token\"") && !strcontains(base64decode(azurerm_linux_virtual_machine_scale_set.agent["general"].custom_data), "rke2-tls-server-ca-key")
    error_message = "agents fetch the agent token and nothing else"
  }
  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "rke2-tls-service-key=tls/service.key") && strcontains(base64decode(azurerm_linux_virtual_machine.server[0].custom_data), "azure-cloud-config.yaml")
    error_message = "servers fetch the CA set and carry the cloud provider manifests"
  }
}

run "etcd_disk_per_server_by_default" {
  command = plan
  assert {
    condition     = length(azurerm_managed_disk.etcd) == 3 && alltrue([for d in azurerm_managed_disk.etcd : d.storage_account_type == "PremiumV2_LRS" && d.disk_size_gb == 64 && d.disk_iops_read_write == 3000 && d.disk_mbps_read_write == 125])
    error_message = "every server gets a Premium SSD v2 disk for etcd by default"
  }
  assert {
    condition     = tolist([for d in azurerm_managed_disk.etcd : d.zone]) == tolist([for s in azurerm_linux_virtual_machine.server : s.zone]) && alltrue([for a in azurerm_virtual_machine_data_disk_attachment.etcd : a.lun == 0 && a.caching == "None"])
    error_message = "the disk sits in its server's zone, at LUN 0, without host cache"
  }
}

run "etcd_disk_off_keeps_etcd_on_the_root_disk" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4s_v5", etcd_disk = { enabled = false } }
  }
  assert {
    condition     = length(azurerm_managed_disk.etcd) == 0 && length(azurerm_virtual_machine_data_disk_attachment.etcd) == 0
    error_message = "etcd_disk.enabled = false creates no disk"
  }
}

run "pool_labels_and_taints_tag_the_scale_set_for_a_scale_from_zero" {
  command = plan
  variables {
    agent_pools = {
      general = { vm_size = "Standard_D4s_v5" }
      labs = {
        vm_size    = "Standard_E4ds_v4"
        node_count = 0
        min_count  = 0
        max_count  = 2
        labels     = { "pelo.tech/usage" = "labs", "tier_a" = "x" }
        taints     = { tenant = { key = "pelo.tech/tenant", value = "uki", effect = "NoSchedule" } }
      }
    }
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["labs"].instances == 0 && azurerm_linux_virtual_machine_scale_set.agent["labs"].tags["min"] == "0"
    error_message = "a pool may start empty"
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.agent["labs"].tags["k8s.io_cluster-autoscaler_node-template_label_pelo.tech_usage"] == "labs" && azurerm_linux_virtual_machine_scale_set.agent["labs"].tags["k8s.io_cluster-autoscaler_node-template_label_tier~2a"] == "x" && azurerm_linux_virtual_machine_scale_set.agent["labs"].tags["k8s.io_cluster-autoscaler_node-template_taint_pelo.tech_tenant"] == "uki:NoSchedule"
    error_message = "the scale set tells the autoscaler the labels and taints of a node it has not created yet"
  }
  assert {
    condition     = !anytrue([for k in keys(azurerm_linux_virtual_machine_scale_set.agent["general"].tags) : startswith(k, "k8s.io_cluster-autoscaler")])
    error_message = "a pool without bounds carries no autoscaler tags"
  }
}
