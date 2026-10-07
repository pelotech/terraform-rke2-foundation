# Input validations. Every run expects a failure on one variable, except the one that proves an accepted value.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

run "azure_cloud_must_be_known" {
  command = plan
  variables {
    azure_cloud = "germany"
  }
  expect_failures = [var.azure_cloud]
}

run "name_follows_hostname_rules" {
  command = plan
  variables {
    name = "Bad_Name"
  }
  expect_failures = [var.name]
}

run "name_leaves_room_for_node_names" {
  command = plan
  variables {
    name = "a-very-long-cluster-name-that-does-not-fit-in-a-hostname"
  }
  expect_failures = [var.name]
}

run "rke2_version_is_a_full_release" {
  command = plan
  variables {
    rke2_version = "1.35"
  }
  expect_failures = [var.rke2_version]
}

run "servers_count_must_be_odd" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4s_v5", count = 2 }
  }
  expect_failures = [var.servers]
}

run "servers_count_must_be_positive" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4s_v5", count = -1 }
  }
  expect_failures = [var.servers]
}

run "premium_disk_needs_a_premium_size" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4d_v4" }
  }
  expect_failures = [var.servers]
}

run "standard_disk_accepts_any_size" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4d_v4", os_disk_type = "StandardSSD_LRS" }
  }
  assert {
    condition     = azurerm_linux_virtual_machine.server[0].size == "Standard_D4d_v4"
    error_message = "a non-premium disk type lifts the size rule"
  }
}

run "agent_pool_premium_disk_needs_a_premium_size" {
  command = plan
  variables {
    agent_pools = { general = { vm_size = "Standard_D4d_v4" } }
  }
  expect_failures = [var.agent_pools]
}

run "cni_pool_premium_disk_needs_a_premium_size" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { vm_size = "Standard_D4d_v4" }
  }
  expect_failures = [var.cni_node_pool]
}

run "servers_disk_type_must_be_known" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4s_v5", os_disk_type = "UltraSSD_LRS" }
  }
  expect_failures = [var.servers]
}

run "agent_pools_cannot_be_empty" {
  command = plan
  variables {
    agent_pools = {}
  }
  expect_failures = [var.agent_pools]
}

run "agent_pool_cannot_be_named_cni" {
  command = plan
  variables {
    agent_pools = { cni = { vm_size = "Standard_D4s_v5" } }
  }
  expect_failures = [var.agent_pools]
}

run "agent_pool_names_are_short_lowercase" {
  command = plan
  variables {
    agent_pools = { "General-Purpose" = { vm_size = "Standard_D4s_v5" } }
  }
  expect_failures = [var.agent_pools]
}

run "agent_pool_min_and_max_come_together" {
  command = plan
  variables {
    agent_pools = { general = { vm_size = "Standard_D4s_v5", min_count = 1 } }
  }
  expect_failures = [var.agent_pools]
}

run "agent_pool_counts_must_be_ordered" {
  command = plan
  variables {
    agent_pools = { general = { vm_size = "Standard_D4s_v5", min_count = 2, node_count = 1, max_count = 5 } }
  }
  expect_failures = [var.agent_pools]
}

run "agent_pool_taint_effect_must_be_known" {
  command = plan
  variables {
    agent_pools = { general = { vm_size = "Standard_D4s_v5", taints = { t = { key = "k", value = "v", effect = "Never" } } } }
  }
  expect_failures = [var.agent_pools]
}

run "cni_must_be_a_known_profile" {
  command = plan
  variables {
    cni = "calico"
  }
  expect_failures = [var.cni]
}

run "cni_node_pool_disk_type_must_be_known" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { os_disk_type = "UltraSSD_LRS" }
  }
  expect_failures = [var.cni_node_pool]
}

run "cni_node_pool_needs_a_node" {
  command = plan
  variables {
    cni           = "kube-ovn"
    cni_node_pool = { node_count = 0 }
  }
  expect_failures = [var.cni_node_pool]
}

run "existing_vnet_subnet_id_must_be_a_subnet" {
  command = plan
  variables {
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
    }
  }
  expect_failures = [var.existing_vnet]
}

run "existing_vnet_api_private_ip_must_be_an_address" {
  command = plan
  variables {
    existing_vnet = {
      vnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
      node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
      api_private_ip = "10.1.0.4/32"
    }
  }
  expect_failures = [var.existing_vnet]
}

run "nat_public_ip_count_has_bounds" {
  command = plan
  variables {
    nat_gateway = { public_ip_count = 0 }
  }
  expect_failures = [var.nat_gateway]
}

run "service_cidr_must_be_smaller_than_a_slash_12" {
  command = plan
  variables {
    service_cidr = "10.0.0.0/12"
  }
  expect_failures = [var.service_cidr]
}

run "pod_cidr_must_not_overlap_service_cidr" {
  command = plan
  variables {
    pod_cidr = "10.96.0.0/16"
  }
  expect_failures = [var.pod_cidr]
}

run "pod_cidr_must_not_overlap_the_vnet" {
  command = plan
  variables {
    vnet = { cidr = "10.240.0.0/12" }
  }
  expect_failures = [var.pod_cidr]
}

run "service_cidr_must_not_overlap_the_vnet" {
  command = plan
  variables {
    vnet = { cidr = "10.96.0.0/12" }
  }
  expect_failures = [var.service_cidr]
}

run "dns_service_ip_must_be_inside_service_cidr" {
  command = plan
  variables {
    dns_service_ip = "10.200.0.10"
  }
  expect_failures = [var.dns_service_ip]
}

run "dns_service_ip_must_not_be_the_first_address" {
  command = plan
  variables {
    dns_service_ip = "10.96.0.1"
  }
  expect_failures = [var.dns_service_ip]
}

run "authorized_ip_ranges_need_a_public_endpoint" {
  command = plan
  variables {
    cluster_endpoint_public_access        = false
    cluster_endpoint_authorized_ip_ranges = ["203.0.113.0/24"]
  }
  expect_failures = [var.cluster_endpoint_authorized_ip_ranges]
}

run "dns_label_follows_azure_rules" {
  command = plan
  variables {
    cluster_endpoint_dns_label = "Platform.Dev"
  }
  expect_failures = [var.cluster_endpoint_dns_label]
}

run "key_vault_network_access_must_be_public_or_private" {
  command = plan
  variables {
    key_vault = { network_access = "Hybrid" }
  }
  expect_failures = [var.key_vault]
}

run "key_vault_name_follows_azure_rules" {
  command = plan
  variables {
    key_vault = { name = "1-starts-with-a-digit" }
  }
  expect_failures = [var.key_vault]
}

run "disable_components_must_be_packaged_components" {
  command = plan
  variables {
    disable_components = ["rke2-canal"]
  }
  expect_failures = [var.disable_components]
}

run "entra_oidc_needs_a_client_id" {
  command = plan
  variables {
    entra_oidc = { enabled = true }
  }
  expect_failures = [var.entra_oidc]
}

run "kube_exec_login_mode_must_be_a_kubelogin_mode" {
  command = plan
  variables {
    kube_exec_login_mode = "password"
  }
  expect_failures = [var.kube_exec_login_mode]
}

run "blob_csi_name_must_be_a_storage_account_name" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "Has-Hyphens" }
  }
  expect_failures = [var.blob_csi]
}

run "oidc_storage_account_name_must_be_a_storage_account_name" {
  command = plan
  variables {
    workload_identity = { oidc_storage_account_name = "Has-Hyphens" }
  }
  expect_failures = [var.workload_identity]
}

run "admin_username_follows_linux_rules" {
  command = plan
  variables {
    admin_username = "Admin User"
  }
  expect_failures = [var.admin_username]
}

run "rke2_version_must_be_1_36_or_newer" {
  command = plan
  variables {
    rke2_version = "v1.35.9+rke2r1"
  }
  expect_failures = [var.rke2_version]
}

run "ingress_controller_must_be_known" {
  command = plan
  variables {
    ingress_controller = "nginx"
  }
  expect_failures = [var.ingress_controller]
}

run "cloud_provider_image_tag_looks_like_a_version" {
  command = plan
  variables {
    cloud_provider_image_tag = "1.37.0"
  }
  expect_failures = [var.cloud_provider_image_tag]
}

run "etcd_disk_keeps_the_premium_v2_baseline" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4s_v5", etcd_disk = { iops = 1000 } }
  }
  expect_failures = [var.servers]
}

run "servers_bootstrap_wait_seconds_has_a_floor" {
  command = plan
  variables {
    servers = { vm_size = "Standard_D4s_v5", bootstrap_wait_seconds = 5 }
  }
  expect_failures = [var.servers]
}

run "agent_pool_os_disk_type_must_be_known" {
  command = plan
  variables {
    agent_pools = { general = { vm_size = "Standard_D4s_v5", os_disk_type = "UltraSSD_LRS" } }
  }
  expect_failures = [var.agent_pools]
}

run "nat_gateway_idle_timeout_in_range" {
  command = plan
  variables {
    nat_gateway = { idle_timeout_minutes = 1 }
  }
  expect_failures = [var.nat_gateway]
}

run "pod_cidr_must_be_a_cidr" {
  command = plan
  variables {
    pod_cidr = "not-a-cidr"
  }
  expect_failures = [var.pod_cidr]
}

run "etcd_backup_replication_type_must_be_known" {
  command = plan
  variables {
    etcd_backup = { replication_type = "RAGRS" }
  }
  expect_failures = [var.etcd_backup]
}

run "etcd_backup_storage_account_name_format" {
  command = plan
  variables {
    etcd_backup = { storage_account_name = "Bad_Name" }
  }
  expect_failures = [var.etcd_backup]
}

run "blob_csi_network_access_must_be_known" {
  command = plan
  variables {
    blob_csi = { enabled = true, network_access = "Open" }
  }
  expect_failures = [var.blob_csi]
}

run "blob_csi_container_names_format" {
  command = plan
  variables {
    blob_csi = { enabled = true, containers = ["Bad Name"] }
  }
  expect_failures = [var.blob_csi]
}

run "extra_server_config_must_be_a_map" {
  command = plan
  variables {
    extra_server_config = "cni: none"
  }
  expect_failures = [var.extra_server_config]
}

run "extra_agent_config_must_be_a_map" {
  command = plan
  variables {
    extra_agent_config = "cni: none"
  }
  expect_failures = [var.extra_agent_config]
}
