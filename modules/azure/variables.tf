variable "name" {
  type        = string
  description = "Name of the cluster. It is the base of every generated resource name and of the node hostnames."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 characters of lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "location" {
  type        = string
  description = "Azure region for every resource, for example usgovvirginia."
}

variable "azure_cloud" {
  type        = string
  description = "Azure cloud: public or usgovernment. It selects the cloud provider environment, the Key Vault audience and the kubelogin environment. Set it to the same cloud as your azurerm provider."

  validation {
    condition     = contains(["public", "usgovernment"], var.azure_cloud)
    error_message = "azure_cloud must be one of: public, usgovernment."
  }
}

variable "resource_group" {
  type = object({
    name   = string
    create = bool
  })
  nullable    = false
  description = "Resource group for the network, Key Vault, identities and load balancers. create = false uses the existing group of that name without managing it."
}

variable "node_resource_group" {
  type = object({
    name   = string
    create = bool
  })
  nullable    = false
  description = "Resource group for the nodes and what the cloud provider and CSI drivers create. create = false looks the existing group up without owning its lifecycle. It may be the same group as resource_group."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource."
}

variable "rke2_version" {
  # renovate: datasource=github-releases depName=rancher/rke2 versioning=regex:^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\+rke2r(?<build>\d+)$
  type        = string
  default     = "v1.37.1+rke2r1"
  description = "RKE2 release every node installs, v1.36.0+rke2r1 or newer. Changing it affects new nodes only; see the README section \"Upgrades\"."

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+\\+rke2r\\d+$", var.rke2_version))
    error_message = "rke2_version must be a full RKE2 release, for example v1.36.5+rke2r1."
  }

  validation {
    condition     = try(tonumber(regex("^v1\\.(\\d+)\\.", var.rke2_version)[0]) >= 36, false)
    error_message = "rke2_version must be v1.36.0+rke2r1 or newer: the module sets ingress-controller, which older releases do not know."
  }
}

variable "cloud_provider_chart_version" {
  # renovate: datasource=helm depName=cloud-provider-azure registryUrl=https://raw.githubusercontent.com/kubernetes-sigs/cloud-provider-azure/master/helm/repo
  type        = string
  default     = "1.36.0"
  description = "cloud-provider-azure chart version. Keep its MAJOR.MINOR equal to the Kubernetes minor in rke2_version, or set cloud_provider_image_tag when the chart lags Kubernetes."
}

variable "cloud_provider_image_tag" {
  # renovate: datasource=docker depName=mcr.microsoft.com/oss/v2/kubernetes/azure-cloud-controller-manager
  type        = string
  default     = "v1.37.0"
  description = "Image tag of the cloud-provider-azure controller and node manager, whose minor must equal the Kubernetes minor. null keeps the chart's own tag. Set it when the chart lags Kubernetes."

  validation {
    condition     = var.cloud_provider_image_tag == null ? true : can(regex("^v\\d+\\.\\d+\\.\\d+", var.cloud_provider_image_tag))
    error_message = "cloud_provider_image_tag must look like v1.37.0, or be null."
  }
}

variable "install_artifact_path" {
  type        = string
  default     = null
  description = "Absolute path baked into each node image containing install.sh, the pinned RKE2 binary tarball and release checksum file. null keeps the online installer. Offline images must include OS/SELinux/kernel dependencies and all required image archives."

  validation {
    condition     = var.install_artifact_path == null ? true : can(regex("^(/[A-Za-z0-9_.-]+)+$", var.install_artifact_path))
    error_message = "install_artifact_path must be an absolute directory path using letters, digits, underscores, dots and hyphens."
  }
}

variable "cloud_provider_chart_url" {
  type        = string
  default     = null
  description = "Where the cloud-provider-azure chart comes from instead of the upstream repository: the oci:// path of the chart in a registry, installed at cloud_provider_chart_version with cloud_provider_chart_credential and registry_ca_pem, or the complete HTTPS URL of a chart archive."

  validation {
    condition     = var.cloud_provider_chart_url == null ? true : can(regex("^(https|oci)://[^[:space:]]+$", var.cloud_provider_chart_url))
    error_message = "cloud_provider_chart_url must be an oci:// chart path or a complete HTTPS chart archive URL."
  }
}

variable "cloud_provider_chart_credential" {
  type = object({
    username = string
    password = string
  })
  default     = null
  sensitive   = true
  description = "Registry login the Helm job uses to pull the cloud-provider-azure chart from the oci:// cloud_provider_chart_url. null pulls anonymously."

  validation {
    condition     = var.cloud_provider_chart_credential == null || can(regex("^oci://", coalesce(var.cloud_provider_chart_url, "")))
    error_message = "cloud_provider_chart_credential needs an oci:// cloud_provider_chart_url."
  }
}

variable "registries_config" {
  type        = string
  default     = null
  sensitive   = true
  description = "Content of /etc/rancher/rke2/registries.yaml for every node: mirrors, rewrites and registry credentials. It travels as a node secret, never in cloud-init. null writes no file, so nodes pull from the upstream registries."
}

variable "registry_ca_pem" {
  type        = string
  default     = null
  description = "PEM chain of a private registry, written to /etc/rancher/rke2/registry-ca.pem on every node before RKE2 starts. Reference that path as ca_file in registries_config."
}

variable "image" {
  type = object({
    id        = optional(string)
    publisher = optional(string, "RedHat")
    offer     = optional(string, "RHEL")
    sku       = optional(string, "10_2-gen2")
    version   = optional(string, "10.2.2026080415")
    plan = optional(object({
      name      = string
      product   = string
      publisher = string
    }))
  })
  default     = {}
  nullable    = false
  description = "Image for every node. Set id to a managed image or an exact Azure Compute Gallery version; otherwise use the pinned RHEL 10.2 Marketplace reference. Set plan when the source image requires purchase terms. Image changes require deliberate server replacement and pool rolling."

  validation {
    condition     = var.image.id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Compute/(images/[^/]+|galleries/[^/]+/images/[^/]+/versions/[0-9]+\\.[0-9]+\\.[0-9]+)$", var.image.id))
    error_message = "image.id must be a managed image ID or an exact gallery image version ID; gallery definitions and latest are not accepted."
  }
}

variable "admin_username" {
  type        = string
  default     = "rke2admin"
  description = "Linux admin user on every node, with ssh_public_key."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,31}$", var.admin_username))
    error_message = "admin_username must be 1-32 characters of lowercase letters, digits, underscores and hyphens, starting with a letter."
  }
}

variable "ssh_public_key" {
  type        = string
  default     = null
  description = "OpenSSH public key for admin_username on every node. null generates an RSA key pair and stores the private key in the Key Vault as ssh-private-key."
}

variable "servers" {
  type = object({
    vm_size                = string
    count                  = optional(number, 3)
    zones                  = optional(list(string), ["1", "2", "3"])
    os_disk_size_gb        = optional(number, 100)
    os_disk_type           = optional(string, "Premium_LRS")
    labels                 = optional(map(string), {})
    schedulable            = optional(bool, false)
    bootstrap_wait_seconds = optional(number, 90)
    etcd_disk = optional(object({
      enabled = optional(bool, true)
      size_gb = optional(number, 64)
      iops    = optional(number, 3000)
      mbps    = optional(number, 125)
    }), {})
  })
  nullable    = false
  description = "Control plane VMs. count must be odd. Servers carry the CriticalAddonsOnly and control-plane taints unless schedulable is true. zones round-robin across the servers; empty means no zone. etcd_disk is a Premium SSD v2 data disk per server for the etcd directory, with no host cache, replaced together with its VM; iops and mbps start at the 3000 and 125 the SKU includes."

  validation {
    condition     = var.servers.count >= 1 && var.servers.count % 2 == 1
    error_message = "servers.count must be a positive odd number: etcd needs an odd quorum."
  }
  validation {
    condition     = contains(local.os_disk_types, var.servers.os_disk_type)
    error_message = "servers.os_disk_type must be one of: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
  validation {
    condition     = var.servers.bootstrap_wait_seconds >= 10
    error_message = "servers.bootstrap_wait_seconds must be at least 10."
  }
  validation {
    condition     = !startswith(var.servers.os_disk_type, "Premium") || can(regex(local.premium_capable_size, var.servers.vm_size))
    error_message = "servers.vm_size does not support Premium disks: pick a size with an s in its suffix, such as Standard_D4s_v5, or set os_disk_type to StandardSSD_LRS."
  }
  validation {
    condition     = var.servers.etcd_disk.size_gb >= 1 && var.servers.etcd_disk.iops >= 3000 && var.servers.etcd_disk.mbps >= 125
    error_message = "servers.etcd_disk: size_gb at least 1, iops at least 3000 and mbps at least 125, the Premium SSD v2 baseline."
  }
}

variable "agent_pools" {
  type = map(object({
    vm_size         = string
    node_count      = optional(number, 1)
    min_count       = optional(number)
    max_count       = optional(number)
    zones           = optional(list(string), ["1", "2", "3"])
    os_disk_size_gb = optional(number, 100)
    os_disk_type    = optional(string, "Premium_LRS")
    labels          = optional(map(string), {})
    taints = optional(map(object({
      key    = string
      value  = string
      effect = string
    })), {})
    load_balancer_backend_address_pool_ids = optional(list(string), [])
  }))
  nullable    = false
  description = "Agent scale sets, keyed by pool name. node_count is the initial size; set min_count and max_count to tag the pool for cluster-autoscaler, which then owns the size. load_balancer_backend_address_pool_ids joins the pool to backend pools of a load balancer the caller owns, at creation only. The README section \"Agent pools\" explains the rest."

  validation {
    condition     = length(var.agent_pools) > 0
    error_message = "agent_pools needs at least one pool: servers carry the CriticalAddonsOnly and control-plane taints, so workloads need agents."
  }
  validation {
    condition     = alltrue([for k in keys(var.agent_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", k)) && k != "cni"])
    error_message = "agent_pools keys must be 1-12 lowercase letters and digits, starting with a letter, and not cni, which the kube-ovn profile uses."
  }
  validation {
    condition     = alltrue([for p in values(var.agent_pools) : (p.min_count == null) == (p.max_count == null)])
    error_message = "agent_pools min_count and max_count must be set together."
  }
  validation {
    condition     = alltrue([for p in values(var.agent_pools) : p.min_count == null || p.max_count == null ? p.node_count >= 0 : p.min_count <= p.node_count && p.node_count <= p.max_count])
    error_message = "agent_pools counts must satisfy min_count <= node_count <= max_count."
  }
  validation {
    condition     = alltrue(flatten([for p in values(var.agent_pools) : [for t in values(p.taints) : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)]]))
    error_message = "agent_pools taint effects must be NoSchedule, PreferNoSchedule or NoExecute."
  }
  validation {
    condition     = alltrue([for p in values(var.agent_pools) : contains(local.os_disk_types, p.os_disk_type)])
    error_message = "agent_pools os_disk_type must be one of: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
  validation {
    condition     = alltrue([for p in values(var.agent_pools) : !startswith(p.os_disk_type, "Premium") || can(regex(local.premium_capable_size, p.vm_size))])
    error_message = "an agent_pools vm_size does not support Premium disks: pick a size with an s in its suffix, such as Standard_D4s_v5, or set that pool's os_disk_type to StandardSSD_LRS."
  }
}

variable "cni" {
  type = object({
    name = string
    node_pool = optional(object({
      vm_size         = string
      zones           = optional(list(string), ["1", "2", "3"])
      node_count      = optional(number, 1)
      os_disk_size_gb = optional(number, 100)
      os_disk_type    = optional(string, "Premium_LRS")
    }))
  })
  nullable    = false
  description = "name is the CNI to run: cilium, kube-ovn or canal. cilium and kube-ovn set RKE2 cni none and cni-bootstrap installs the CNI; cilium also turns kube-proxy off. canal is the bundled, FIPS-rebuilt CNI. node_pool is the dedicated pool kube-ovn's control plane runs on, the scale set named cni: required for kube-ovn, absent for the others. To recycle it, replace the scale set with terraform apply -replace."

  validation {
    condition     = contains(keys(local.cni_profiles), var.cni.name)
    error_message = "cni.name must be one of: cilium, kube-ovn, canal."
  }
  validation {
    condition     = (var.cni.name == "kube-ovn") == (var.cni.node_pool != null)
    error_message = "cni.node_pool is required for kube-ovn and must be absent for cilium and canal."
  }
  validation {
    condition     = var.cni.node_pool == null ? true : var.cni.node_pool.node_count >= 1
    error_message = "cni.node_pool.node_count must be at least 1."
  }
  validation {
    condition     = var.cni.node_pool == null ? true : contains(local.os_disk_types, var.cni.node_pool.os_disk_type)
    error_message = "cni.node_pool.os_disk_type must be one of: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
  validation {
    condition     = var.cni.node_pool == null ? true : !startswith(var.cni.node_pool.os_disk_type, "Premium") || can(regex(local.premium_capable_size, var.cni.node_pool.vm_size))
    error_message = "cni.node_pool.vm_size does not support Premium disks: pick a size with an s in its suffix, such as Standard_D4s_v5, or set os_disk_type to StandardSSD_LRS."
  }
}

variable "network" {
  type = object({
    create = optional(object({
      address_space     = optional(string, "10.0.0.0/16")
      node_subnet       = optional(string, "10.0.0.0/22")
      service_endpoints = optional(list(string), [])
      nat_gateway = optional(object({
        public_ip_count      = optional(number, 1)
        idle_timeout_minutes = optional(number, 4)
      }), {})
    }))
    existing = optional(object({
      vnet_id           = string
      node_subnet_id    = string
      security_group_id = string
      api_private_ip    = optional(string)
    }))
  })
  nullable    = false
  description = "Exactly one of create or existing. create builds a VNet with address_space, a node subnet of node_subnet for every VM, the API private address and private endpoints, and a NAT Gateway for egress. existing joins the given VNet and node subnet, creates no network and no NAT Gateway, so the subnet must provide egress; security_group_id is the network security group on that subnet, where cloud-provider-azure adds the rules for LoadBalancer Services and the server identity gets Network Contributor; api_private_ip is the static address of the API load balancer, null lets Azure pick one."

  validation {
    condition     = (var.network.create == null) != (var.network.existing == null)
    error_message = "network needs exactly one of create or existing."
  }
  validation {
    condition     = var.network.existing == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.network.existing.node_subnet_id))
    error_message = "network.existing.node_subnet_id must be a subnet resource id: /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
  validation {
    condition     = var.network.existing == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/networkSecurityGroups/[^/]+$", var.network.existing.security_group_id))
    error_message = "network.existing.security_group_id must be a network security group resource id: /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Network/networkSecurityGroups/<name>."
  }
  validation {
    condition     = var.network.existing == null || try(var.network.existing.api_private_ip, null) == null ? true : can(cidrhost("${var.network.existing.api_private_ip}/32", 0))
    error_message = "network.existing.api_private_ip must be an IPv4 address without a prefix length."
  }
  validation {
    condition     = var.network.create == null ? true : can(cidrhost(var.network.create.address_space, 0)) && can(cidrhost(var.network.create.node_subnet, 0))
    error_message = "network.create.address_space and network.create.node_subnet must be IPv4 CIDRs."
  }
  validation {
    condition     = var.network.create == null ? true : var.network.create.nat_gateway.public_ip_count >= 1 && var.network.create.nat_gateway.public_ip_count <= 16
    error_message = "network.create.nat_gateway.public_ip_count must be between 1 and 16."
  }
  validation {
    condition     = var.network.create == null ? true : var.network.create.nat_gateway.idle_timeout_minutes >= 4 && var.network.create.nat_gateway.idle_timeout_minutes <= 120
    error_message = "network.create.nat_gateway.idle_timeout_minutes must be between 4 and 120."
  }
}

variable "private_endpoints" {
  type = map(object({
    resource_id          = string
    subresource_names    = list(string)
    private_dns_zone_ids = list(string)
  }))
  default     = {}
  nullable    = false
  description = "Private endpoints in the node subnet, one for each target resource. You select the key names. Example subresource_names: [\"blob\"], [\"vault\"], [\"registry\"]. An empty private_dns_zone_ids attaches no DNS zone group and leaves the record to the zone's owner."
}

variable "cluster_network" {
  type = object({
    service_cidr   = optional(string, "10.96.0.0/16")
    pod_cidr       = optional(string, "10.244.0.0/16")
    dns_service_ip = optional(string)
  })
  default     = {}
  nullable    = false
  description = "Kubernetes-internal ranges, virtual and never routed in Azure. service_cidr is the ClusterIP range, with a prefix longer than /12; pod_cidr is the RKE2 cluster-cidr the CNI hands to pods. Neither may overlap the other or the VNet. dns_service_ip is the cluster DNS address inside service_cidr, the tenth address by default."

  validation {
    condition     = can(cidrhost(var.cluster_network.service_cidr, 0)) && tonumber(split("/", var.cluster_network.service_cidr)[1]) > 12
    error_message = "cluster_network.service_cidr must be a valid IPv4 CIDR with a prefix longer than /12."
  }
  validation {
    condition     = can(cidrhost(var.cluster_network.pod_cidr, 0))
    error_message = "cluster_network.pod_cidr must be a valid IPv4 CIDR."
  }
  validation {
    # Two CIDRs overlap when one contains the other's network address. Malformed input is left to the format checks.
    condition = !anytrue([for pair in concat(
      [[var.cluster_network.pod_cidr, var.cluster_network.service_cidr]],
      local.vnet_address_space == null ? [] : [[var.cluster_network.pod_cidr, local.vnet_address_space], [var.cluster_network.service_cidr, local.vnet_address_space]],
      ) : try(
      cidrhost("${cidrhost(pair[0], 0)}/${split("/", pair[1])[1]}", 0) == cidrhost(pair[1], 0) ||
      cidrhost("${cidrhost(pair[1], 0)}/${split("/", pair[0])[1]}", 0) == cidrhost(pair[0], 0),
      false,
    )])
    error_message = "cluster_network.pod_cidr and cluster_network.service_cidr must not overlap each other or network.create.address_space."
  }
  validation {
    condition     = var.cluster_network.dns_service_ip == null ? true : (cidrhost("${var.cluster_network.dns_service_ip}/${split("/", var.cluster_network.service_cidr)[1]}", 0) == cidrhost(var.cluster_network.service_cidr, 0) && var.cluster_network.dns_service_ip != cidrhost(var.cluster_network.service_cidr, 1))
    error_message = "cluster_network.dns_service_ip must be inside service_cidr and must not be its first address, which Kubernetes reserves for the kubernetes service."
  }
}

variable "cluster_endpoint" {
  type = object({
    public               = bool
    authorized_ip_ranges = optional(list(string), [])
    dns_label            = optional(string)
  })
  nullable    = false
  description = "public adds a public load balancer in front of the API server, reachable only from authorized_ip_ranges, which is then required: 0.0.0.0/0 opens it to the internet, write it only when you mean it. false keeps only the internal one, which needs VNet connectivity to apply cni-bootstrap. dns_label names the public address, unique per region; null generates <name>-<hash>."

  validation {
    condition     = var.cluster_endpoint.public == (length(var.cluster_endpoint.authorized_ip_ranges) > 0)
    error_message = "cluster_endpoint.authorized_ip_ranges must list at least one CIDR for a public endpoint and must be empty for a private one."
  }
  validation {
    condition     = var.cluster_endpoint.dns_label == null ? true : can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.cluster_endpoint.dns_label))
    error_message = "cluster_endpoint.dns_label must be 3-63 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "key_vault" {
  type = object({
    admin_object_ids = list(string)
    name             = optional(string)
    network_access   = optional(string, "Public")
  })
  nullable    = false
  description = "Key Vault holding the join tokens, the CA set and the generated SSH key. admin_object_ids must include the principal that applies the module: it writes the secrets. After a destroy, Azure keeps the vault soft-deleted for 90 days, and the next apply recovers it with its secrets."

  validation {
    condition     = length(var.key_vault.admin_object_ids) > 0
    error_message = "key_vault.admin_object_ids must include the principal that applies the module: it writes the secrets."
  }
  validation {
    condition     = contains(["Public", "Private"], var.key_vault.network_access)
    error_message = "key_vault.network_access must be one of: Public, Private."
  }
  validation {
    # RE2 has no lookahead, so the consecutive-hyphen rule is a separate strcontains check.
    condition     = var.key_vault.name == null ? true : (can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault.name)) && !strcontains(var.key_vault.name, "--"))
    error_message = "key_vault.name must be 3-24 characters of letters, digits and single hyphens, start with a letter and end with a letter or digit."
  }
}

variable "secrets_encryption" {
  type        = bool
  default     = true
  description = "Encrypts Secrets at rest in etcd with RKE2's secrets-encryption."
}

variable "etcd_backup" {
  type = object({
    storage_account_name = string
    retention_days       = optional(number, 30)
    replication_type     = optional(string, "LRS")
    network_access       = optional(string, "NodeSubnet")
    private_dns_zone_ids = optional(list(string), [])
  })
  description = "Hourly upload of each new etcd snapshot from every server to a private storage account of its own, named storage_account_name, with the server identity, under <name>/<server>/<file>. null uploads nothing. Blob versioning and soft delete are on, and a lifecycle rule deletes snapshots after retention_days. network_access is NodeSubnet (default, requires Microsoft.Storage on an existing subnet) or PrivateEndpoint (public networking disabled, Blob endpoint in the node subnet, integrated with private_dns_zone_ids when given, otherwise the zone's owner creates the record)."

  validation {
    condition     = var.etcd_backup == null ? true : contains(["NodeSubnet", "PrivateEndpoint"], var.etcd_backup.network_access)
    error_message = "etcd_backup.network_access must be NodeSubnet or PrivateEndpoint."
  }
  validation {
    condition     = var.etcd_backup == null ? true : var.etcd_backup.network_access == "PrivateEndpoint" || length(var.etcd_backup.private_dns_zone_ids) == 0
    error_message = "etcd_backup.private_dns_zone_ids needs network_access PrivateEndpoint."
  }
  validation {
    condition     = var.etcd_backup == null ? true : alltrue([for id in var.etcd_backup.private_dns_zone_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", id))])
    error_message = "etcd_backup.private_dns_zone_ids must be private DNS zone resource ids: /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Network/privateDnsZones/<zone>."
  }

  validation {
    condition     = var.etcd_backup == null ? true : var.etcd_backup.retention_days >= 1 && var.etcd_backup.retention_days <= 365
    error_message = "etcd_backup.retention_days must be between 1 and 365."
  }
  validation {
    condition     = var.etcd_backup == null ? true : contains(["LRS", "ZRS", "GRS", "GZRS"], var.etcd_backup.replication_type)
    error_message = "etcd_backup.replication_type must be LRS, ZRS, GRS or GZRS."
  }
  validation {
    condition     = var.etcd_backup == null ? true : can(regex("^[a-z0-9]{3,24}$", var.etcd_backup.storage_account_name))
    error_message = "etcd_backup.storage_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "certificate_renewal" {
  type        = bool
  default     = true
  description = "Renews node certificates on the nodes themselves with a daily timer; see the bootstrap module. Off, the operator renews by restart or replacement."
}

variable "disable_firewalld" {
  type        = bool
  default     = true
  description = "Stops firewalld at bootstrap on images that ship it, such as RHEL. Set false on an image whose firewalld rules allow the RKE2 ports."
}

variable "cis_profile" {
  type        = bool
  default     = false
  description = "Runs RKE2 with profile cis: the CIS host prerequisites, restricted Pod Security Admission and default network policies."
}

variable "disable_components" {
  type        = list(string)
  default     = ["rke2-snapshot-controller", "rke2-snapshot-controller-crd", "rke2-snapshot-validation-webhook"]
  description = "Packaged RKE2 components not to deploy. Default: no snapshot controller, which the GitOps layer provides, as on AKS. The ingress is ingress_controller."

  validation {
    condition = alltrue([
      for c in var.disable_components : contains([
        "rke2-coredns", "rke2-metrics-server", "rke2-snapshot-controller", "rke2-snapshot-controller-crd",
        "rke2-snapshot-validation-webhook", "rke2-security-responder", "rke2-gateway-api-crd",
      ], c)
    ])
    error_message = "disable_components entries must be packaged RKE2 components: rke2-coredns, rke2-metrics-server, rke2-snapshot-controller, rke2-snapshot-controller-crd, rke2-snapshot-validation-webhook, rke2-security-responder, rke2-gateway-api-crd. The ingress is ingress_controller."
  }
}

variable "ingress_controller" {
  type        = string
  default     = "none"
  description = "Packaged ingress controller: none, traefik or ingress-nginx. The GitOps layer provides the ingress, as on AKS, so the default is none."

  validation {
    condition     = contains(["none", "traefik", "ingress-nginx"], var.ingress_controller)
    error_message = "ingress_controller must be none, traefik or ingress-nginx."
  }
}

variable "kube_apiserver_args" {
  type        = list(string)
  default     = []
  description = "Extra kube-apiserver-arg entries, as flag=value strings, after the ones the module sets."
}

variable "kube_controller_manager_args" {
  type        = list(string)
  default     = []
  description = "Extra kube-controller-manager-arg entries, as flag=value strings."
}

variable "kubelet_args" {
  type        = list(string)
  default     = []
  description = "kubelet-arg entries for every node, as flag=value strings."
}

variable "extra_server_config" {
  type        = any
  default     = {}
  description = "RKE2 server config keys merged last into every server's config.yaml. They override the module's keys."

  validation {
    condition     = can(keys(var.extra_server_config))
    error_message = "extra_server_config must be a map or object of RKE2 config keys."
  }
}

variable "extra_agent_config" {
  type        = any
  default     = {}
  description = "RKE2 agent config keys merged last into every agent's config.yaml. They override the module's keys."

  validation {
    condition     = can(keys(var.extra_agent_config))
    error_message = "extra_agent_config must be a map or object of RKE2 config keys."
  }
}

variable "workload_identity" {
  type = object({
    storage_account_name = string
    external_dns         = optional(object({ dns_zone_ids = optional(list(string), []) }))
    cert_manager         = optional(object({ dns_zone_ids = optional(list(string), []) }))
  })
  description = "The cluster's OIDC issuer for Microsoft Entra Workload ID, published from the static website of the storage account named storage_account_name, and one Entra identity per controller listed: external_dns and cert_manager, each with the DNS zones it gets DNS Zone Contributor on. null creates no issuer and no identity. Set it at the first apply when workloads will ever need it: turning the issuer on later changes the service account issuer and replaces every server."

  validation {
    condition     = var.workload_identity == null ? true : can(regex("^[a-z0-9]{3,24}$", var.workload_identity.storage_account_name))
    error_message = "workload_identity.storage_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "blob_csi" {
  type = object({
    storage_account_name      = string
    containers                = optional(list(string), [])
    network_access            = optional(string, "NodeSubnet")
    extra_subnet_ids          = optional(list(string), [])
    shared_access_key_enabled = optional(bool, false)
    private_dns_zone_ids      = optional(list(string), [])
  })
  description = "Blob storage for the blob CSI driver: a storage account named storage_account_name, the agent identity grant and one private container per name in containers. null creates nothing. network_access is NodeSubnet, Public or PrivateEndpoint; extra_subnet_ids extends NodeSubnet access only, and private_dns_zone_ids attaches the DNS zone group behind PrivateEndpoint; leave it empty when the zone's owner creates the record. The README section \"Storage\" explains each field."

  validation {
    condition     = var.blob_csi == null ? true : var.blob_csi.network_access == "PrivateEndpoint" || length(var.blob_csi.private_dns_zone_ids) == 0
    error_message = "blob_csi.private_dns_zone_ids needs network_access PrivateEndpoint."
  }
  validation {
    condition     = var.blob_csi == null ? true : alltrue([for id in var.blob_csi.private_dns_zone_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", id))])
    error_message = "blob_csi.private_dns_zone_ids must be private DNS zone resource ids: /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Network/privateDnsZones/<zone>."
  }
  validation {
    condition     = var.blob_csi == null ? true : var.blob_csi.network_access == "NodeSubnet" || length(var.blob_csi.extra_subnet_ids) == 0
    error_message = "blob_csi.extra_subnet_ids extends NodeSubnet access only; with Public or PrivateEndpoint access it would be ignored."
  }

  validation {
    condition     = var.blob_csi == null ? true : contains(["NodeSubnet", "Public", "PrivateEndpoint"], var.blob_csi.network_access)
    error_message = "blob_csi.network_access must be one of: NodeSubnet, Public, PrivateEndpoint."
  }
  validation {
    condition     = var.blob_csi == null ? true : can(regex("^[a-z0-9]{3,24}$", var.blob_csi.storage_account_name))
    error_message = "blob_csi.storage_account_name must be 3-24 lowercase letters and digits."
  }
  validation {
    condition     = var.blob_csi == null ? true : alltrue([for name in var.blob_csi.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name))])
    error_message = "blob_csi.containers names must be 3-63 lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "entra_oidc" {
  type = object({
    client_id              = string
    login_mode             = string
    admin_group_object_ids = optional(list(string), [])
    admin_object_ids       = optional(list(string), [])
    reader_object_ids      = optional(list(string), [])
    issuer_url             = optional(string)
    username_claim         = optional(string, "oid")
    groups_claim           = optional(string, "groups")
    username_prefix        = optional(string)
  })
  description = "Microsoft Entra ID as the API server's OIDC provider, for kubectl through kubelogin. null keeps the admin client certificate as the only credential. client_id is an app registration you own, with token version 2 and group claims; issuer_url defaults to the tenant's v2 endpoint in azure_cloud. login_mode is the kubelogin --login mode in kube_exec: azurecli reuses your az session; spn, msi, workloadidentity or azurepipelines in CI. The username claim is oid, present in user and service principal tokens alike. Servers apply a ClusterRoleBinding to cluster-admin for admin_group_object_ids and admin_object_ids, and read-only bindings for reader_object_ids, before the first node joins. The principal that applies the module must be in an admin list: it installs the CNI through kube_exec. The README section \"Access\" lists what the app registration needs."

  validation {
    condition     = var.entra_oidc == null ? true : length(concat(var.entra_oidc.admin_group_object_ids, var.entra_oidc.admin_object_ids)) > 0
    error_message = "entra_oidc needs at least one admin subject in admin_group_object_ids or admin_object_ids: Terraform signs in through Entra and must be cluster-admin."
  }
  validation {
    condition     = var.entra_oidc == null ? true : contains(["devicecode", "interactive", "spn", "ropc", "msi", "azurecli", "azd", "workloadidentity", "azurepipelines"], var.entra_oidc.login_mode)
    error_message = "entra_oidc.login_mode must be a kubelogin login mode: devicecode, interactive, spn, ropc, msi, azurecli, azd, workloadidentity, azurepipelines."
  }
}

variable "pki" {
  type = object({
    ca_validity_hours         = optional(number, 87600)
    admin_validity_hours      = optional(number, 8760)
    admin_early_renewal_hours = optional(number, 720)
  })
  default     = {}
  nullable    = false
  description = "Validity of the CA set and of the admin client certificate, which Terraform renews admin_early_renewal_hours before it expires."
}

# Legacy path, implemented in runtime_credential_legacy.tf; the managed-identity default is the recommended one.
variable "runtime_credential" {
  type = object({
    client_id     = string
    client_secret = string
  })
  default     = null
  sensitive   = true
  description = "Service principal the nodes use instead of managed identities: cloud-provider-azure, the CSI drivers and the snapshot upload authenticate with it, and cloud-init carries the join tokens and CA set instead of the Key Vault. null keeps the default: one managed identity per role with the module's role assignments and the vault. Set it where the applying principal cannot create identities or role assignments; the Key Vault then stays but holds no secrets."
}
