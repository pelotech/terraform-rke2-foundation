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
    cni = { name = "kube-ovn", node_pool = { vm_size = "Standard_D4d_v4" } }
  }
  expect_failures = [var.cni]
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
    cni = { name = "calico" }
  }
  expect_failures = [var.cni]
}

run "kube_ovn_needs_a_node_pool" {
  command = plan
  variables {
    cni = { name = "kube-ovn" }
  }
  expect_failures = [var.cni]
}

run "only_kube_ovn_takes_a_node_pool" {
  command = plan
  variables {
    cni = { name = "cilium", node_pool = { vm_size = "Standard_D4s_v5" } }
  }
  expect_failures = [var.cni]
}

run "cni_node_pool_disk_type_must_be_known" {
  command = plan
  variables {
    cni = { name = "kube-ovn", node_pool = { vm_size = "Standard_D4s_v5", os_disk_type = "UltraSSD_LRS" } }
  }
  expect_failures = [var.cni]
}

run "cni_node_pool_needs_a_node" {
  command = plan
  variables {
    cni = { name = "kube-ovn", node_pool = { vm_size = "Standard_D4s_v5", node_count = 0 } }
  }
  expect_failures = [var.cni]
}

run "existing_network_subnet_id_must_be_a_subnet" {
  command = plan
  variables {
    network = {
      existing = {
        vnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        node_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/networkSecurityGroups/nsg-shared-nodes"
      }
    }
  }
  expect_failures = [var.network]
}

run "existing_network_security_group_id_must_be_a_security_group" {
  command = plan
  variables {
    network = {
      existing = {
        vnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        node_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
        security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
      }
    }
  }
  expect_failures = [var.network]
}

run "network_needs_exactly_one_branch" {
  command = plan
  variables {
    network = {
      create = {}
      existing = {
        vnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        node_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
        security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/networkSecurityGroups/nsg-shared-nodes"
      }
    }
  }
  expect_failures = [var.network]
}

run "network_cannot_be_empty" {
  command = plan
  variables {
    network = {}
  }
  expect_failures = [var.network]
}

run "existing_network_api_private_ip_must_be_an_address" {
  command = plan
  variables {
    network = {
      existing = {
        vnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared"
        node_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-nodes"
        security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/networkSecurityGroups/nsg-shared-nodes"
        api_private_ip    = "10.1.0.4/32"
      }
    }
  }
  expect_failures = [var.network]
}

run "nat_public_ip_count_has_bounds" {
  command = plan
  variables {
    network = { create = { nat_gateway = { public_ip_count = 0 } } }
  }
  expect_failures = [var.network]
}

run "service_cidr_must_be_smaller_than_a_slash_12" {
  command = plan
  variables {
    cluster_network = { service_cidr = "10.0.0.0/12" }
  }
  expect_failures = [var.cluster_network]
}

run "pod_cidr_must_not_overlap_service_cidr" {
  command = plan
  variables {
    cluster_network = { pod_cidr = "10.96.0.0/16" }
  }
  expect_failures = [var.cluster_network]
}

run "pod_cidr_must_not_overlap_the_vnet" {
  command = plan
  variables {
    network = { create = { address_space = "10.240.0.0/12" } }
  }
  expect_failures = [var.cluster_network]
}

run "service_cidr_must_not_overlap_the_vnet" {
  command = plan
  variables {
    network = { create = { address_space = "10.96.0.0/12" } }
  }
  expect_failures = [var.cluster_network]
}

run "dns_service_ip_must_be_inside_service_cidr" {
  command = plan
  variables {
    cluster_network = { dns_service_ip = "10.200.0.10" }
  }
  expect_failures = [var.cluster_network]
}

run "dns_service_ip_must_not_be_the_first_address" {
  command = plan
  variables {
    cluster_network = { dns_service_ip = "10.96.0.1" }
  }
  expect_failures = [var.cluster_network]
}

run "authorized_ip_ranges_need_a_public_endpoint" {
  command = plan
  variables {
    cluster_endpoint = { public = false, authorized_ip_ranges = ["203.0.113.0/24"] }
  }
  expect_failures = [var.cluster_endpoint]
}

run "public_endpoint_needs_authorized_ip_ranges" {
  command = plan
  variables {
    cluster_endpoint = { public = true }
  }
  expect_failures = [var.cluster_endpoint]
}

run "dns_label_follows_azure_rules" {
  command = plan
  variables {
    cluster_endpoint = { public = true, authorized_ip_ranges = ["203.0.113.0/24"], dns_label = "Platform.Dev" }
  }
  expect_failures = [var.cluster_endpoint]
}

run "key_vault_network_access_must_be_public_or_private" {
  command = plan
  variables {
    key_vault = { admin_object_ids = ["00000000-0000-0000-0000-000000000003"], network_access = "Hybrid" }
  }
  expect_failures = [var.key_vault]
}

run "key_vault_needs_an_admin" {
  command = plan
  variables {
    key_vault = { admin_object_ids = [] }
  }
  expect_failures = [var.key_vault]
}

run "key_vault_name_follows_azure_rules" {
  command = plan
  variables {
    key_vault = { admin_object_ids = ["00000000-0000-0000-0000-000000000003"], name = "1-starts-with-a-digit" }
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

run "entra_oidc_needs_an_admin_subject" {
  command = plan
  variables {
    entra_oidc = { client_id = "22222222-2222-2222-2222-222222222222", login_mode = "azurecli" }
  }
  expect_failures = [var.entra_oidc]
}

run "entra_login_mode_must_be_a_kubelogin_mode" {
  command = plan
  variables {
    entra_oidc = { client_id = "22222222-2222-2222-2222-222222222222", login_mode = "password", admin_group_object_ids = ["33333333-3333-3333-3333-333333333333"] }
  }
  expect_failures = [var.entra_oidc]
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
    workload_identity = { storage_account_name = "Has-Hyphens" }
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
    network = { create = { nat_gateway = { idle_timeout_minutes = 1 } } }
  }
  expect_failures = [var.network]
}

run "pod_cidr_must_be_a_cidr" {
  command = plan
  variables {
    cluster_network = { pod_cidr = "not-a-cidr" }
  }
  expect_failures = [var.cluster_network]
}

run "etcd_backup_replication_type_must_be_known" {
  command = plan
  variables {
    etcd_backup = { storage_account_name = "acmeplatformdevetcd", replication_type = "RAGRS" }
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
    blob_csi = { storage_account_name = "acmeplatformdevcsi", network_access = "Open" }
  }
  expect_failures = [var.blob_csi]
}

run "blob_csi_container_names_format" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi", containers = ["Bad Name"] }
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

run "blob_csi_extra_subnets_need_node_subnet_access" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi", network_access = "Public", extra_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-other"] }
  }
  expect_failures = [var.blob_csi]
}

run "blob_csi_extra_subnets_have_no_place_behind_a_private_endpoint" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi", network_access = "PrivateEndpoint", private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-pdns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.usgovcloudapi.net"], extra_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/snet-other"] }
  }
  expect_failures = [var.blob_csi]
}

run "blob_csi_private_dns_zone_ids_must_be_private_dns_zones" {
  command = plan
  variables {
    blob_csi = { storage_account_name = "acmeplatformdevcsi", network_access = "PrivateEndpoint", private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-pdns/providers/Microsoft.Network/dnsZones/example.com"] }
  }
  expect_failures = [var.blob_csi]
}

run "etcd_backup_private_dns_zone_ids_must_be_private_dns_zones" {
  command = plan
  variables {
    etcd_backup = { storage_account_name = "acmeplatformdevetcd", network_access = "PrivateEndpoint", private_dns_zone_ids = ["privatelink.blob.core.usgovcloudapi.net"] }
  }
  expect_failures = [var.etcd_backup]
}
