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
  default     = "public"
  description = "Azure cloud: public or usgovernment. It selects the cloud provider environment, the Key Vault audience and the kubelogin environment. Set it to the same cloud as your azurerm provider."

  validation {
    condition     = contains(["public", "usgovernment"], var.azure_cloud)
    error_message = "azure_cloud must be one of: public, usgovernment."
  }
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Resource group for the network, Key Vault, identities and load balancers. null generates rg-<name>."
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Creates the resource group. Set false to use an existing group named resource_group_name."
}

variable "node_resource_group_name" {
  type        = string
  default     = null
  description = "Resource group the module creates for the nodes and everything the cloud provider and CSI driver create. null generates rg-<name>-nodes."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource. The Owner tag, when present, seeds the storage account names."
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
  description = "Complete HTTPS URL of the pinned cloud-provider-azure chart archive. Overrides the upstream chart repository. For a baked chart under /var/lib/rancher/rke2/server/static/charts, use https://%%{KUBERNETES_API}%/static/charts/<filename>.tgz. The image must carry the corresponding controller/node-manager images."

  validation {
    condition     = var.cloud_provider_chart_url == null ? true : can(regex("^https://[^[:space:]]+$", var.cloud_provider_chart_url))
    error_message = "cloud_provider_chart_url must be a complete HTTPS chart archive URL."
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
  }))
  nullable    = false
  description = "Agent scale sets, keyed by pool name. node_count is the initial size; set min_count and max_count to tag the pool for cluster-autoscaler, which then owns the size. The README section \"Agent pools\" explains the rest."

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
  type        = string
  default     = "cilium"
  description = "CNI to run: cilium, kube-ovn or canal. cilium and kube-ovn set RKE2 cni none and cni-bootstrap installs the CNI; cilium also turns kube-proxy off. canal is the bundled, FIPS-rebuilt CNI. kube-ovn also creates the CNI node pool."

  validation {
    condition     = contains(keys(local.cni_profiles), var.cni)
    error_message = "cni must be one of: cilium, kube-ovn, canal."
  }
}

variable "cni_node_pool" {
  type = object({
    enabled         = optional(bool, true)
    vm_size         = optional(string)
    zones           = optional(list(string))
    node_count      = optional(number, 1)
    os_disk_size_gb = optional(number, 100)
    os_disk_type    = optional(string, "Premium_LRS")
  })
  default     = {}
  nullable    = false
  description = "Dedicated CNI pool, created for kube-ovn as the scale set named cni. vm_size and zones default to the servers'. Set enabled = false, then true, to recycle the pool."

  validation {
    condition     = var.cni_node_pool.node_count >= 1
    error_message = "cni_node_pool.node_count must be at least 1."
  }
  validation {
    condition     = contains(local.os_disk_types, var.cni_node_pool.os_disk_type)
    error_message = "cni_node_pool.os_disk_type must be one of: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
  validation {
    condition     = var.cni_node_pool.vm_size == null || !startswith(var.cni_node_pool.os_disk_type, "Premium") || can(regex(local.premium_capable_size, var.cni_node_pool.vm_size))
    error_message = "cni_node_pool.vm_size does not support Premium disks: pick a size with an s in its suffix, such as Standard_D4s_v5, or set os_disk_type to StandardSSD_LRS."
  }
}

variable "vnet" {
  type = object({
    cidr                 = optional(string, "10.0.0.0/16")
    node_subnet_cidr     = optional(string, "10.0.0.0/22")
    database_subnet_cidr = optional(string)
    service_endpoints    = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "VNet the module creates; ignored when existing_vnet is set. Size node_subnet_cidr for the maximum node count plus private endpoints. The API load balancer takes the subnet's last usable address."
}

variable "existing_vnet" {
  type = object({
    vnet_id        = string
    node_subnet_id = string
    api_private_ip = optional(string)
  })
  default     = null
  description = "Use an existing VNet and node subnet. The module then creates no network and no NAT Gateway, so the subnet must provide egress. api_private_ip is the static address of the API load balancer; null lets Azure pick one."

  validation {
    condition     = var.existing_vnet == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.existing_vnet.node_subnet_id))
    error_message = "existing_vnet.node_subnet_id must be a subnet resource id: /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
  validation {
    condition     = var.existing_vnet == null || try(var.existing_vnet.api_private_ip, null) == null ? true : can(cidrhost("${var.existing_vnet.api_private_ip}/32", 0))
    error_message = "existing_vnet.api_private_ip must be an IPv4 address without a prefix length."
  }
}

variable "nat_gateway" {
  type = object({
    public_ip_count      = optional(number, 1)
    idle_timeout_minutes = optional(number, 4)
  })
  default     = {}
  nullable    = false
  description = "NAT Gateway for node egress, created whenever the module creates the VNet."

  validation {
    condition     = var.nat_gateway.public_ip_count >= 1 && var.nat_gateway.public_ip_count <= 16
    error_message = "nat_gateway.public_ip_count must be between 1 and 16."
  }
  validation {
    condition     = var.nat_gateway.idle_timeout_minutes >= 4 && var.nat_gateway.idle_timeout_minutes <= 120
    error_message = "nat_gateway.idle_timeout_minutes must be between 4 and 120."
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
  description = "Private endpoints in the node subnet, one for each target resource. You select the key names. Example subresource_names: [\"blob\"], [\"vault\"], [\"registry\"]."
}

variable "service_cidr" {
  type        = string
  default     = "10.96.0.0/16"
  description = "Kubernetes service CIDR, with a prefix longer than /12. It must not overlap the VNet or pod_cidr."

  validation {
    condition     = can(cidrhost(var.service_cidr, 0)) && tonumber(split("/", var.service_cidr)[1]) > 12
    error_message = "service_cidr must be a valid IPv4 CIDR with a prefix longer than /12."
  }
  validation {
    # Two CIDRs overlap when one contains the other's network address. Malformed input is left to the format check.
    condition = !anytrue([for other in local.service_cidr_must_avoid : try(
      cidrhost("${cidrhost(var.service_cidr, 0)}/${split("/", other)[1]}", 0) == cidrhost(other, 0) ||
      cidrhost("${cidrhost(other, 0)}/${split("/", var.service_cidr)[1]}", 0) == cidrhost(var.service_cidr, 0),
      false,
    )])
    error_message = "service_cidr must not overlap vnet.cidr."
  }
}

variable "dns_service_ip" {
  type        = string
  default     = null
  description = "Cluster DNS service IP inside service_cidr. null uses the tenth address."

  validation {
    condition     = var.dns_service_ip == null ? true : (cidrhost("${var.dns_service_ip}/${split("/", var.service_cidr)[1]}", 0) == cidrhost(var.service_cidr, 0) && var.dns_service_ip != cidrhost(var.service_cidr, 1))
    error_message = "dns_service_ip must be inside service_cidr and must not be its first address, which Kubernetes reserves for the kubernetes service."
  }
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod CIDR, the RKE2 cluster-cidr. Pass the cluster_pod_cidr output to cni-bootstrap so the CNI uses the same range."

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid IPv4 CIDR."
  }
  validation {
    # One shared local would cycle through the other variable's validation, so the check is written per variable.
    condition = !anytrue([for other in local.pod_cidr_must_avoid : try(
      cidrhost("${cidrhost(var.pod_cidr, 0)}/${split("/", other)[1]}", 0) == cidrhost(other, 0) ||
      cidrhost("${cidrhost(other, 0)}/${split("/", var.pod_cidr)[1]}", 0) == cidrhost(var.pod_cidr, 0),
      false,
    )])
    error_message = "pod_cidr must not overlap vnet.cidr or service_cidr."
  }
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = true
  description = "Adds a public load balancer in front of the API server. false keeps only the internal one, which needs VNet connectivity to apply cni-bootstrap."
}

variable "cluster_endpoint_authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public API server. Empty allows all."

  validation {
    condition     = length(var.cluster_endpoint_authorized_ip_ranges) == 0 || var.cluster_endpoint_public_access
    error_message = "cluster_endpoint_authorized_ip_ranges only applies to a public API server. Unset it or set cluster_endpoint_public_access = true."
  }
}

variable "cluster_endpoint_dns_label" {
  type        = string
  default     = null
  description = "DNS label of the public API address, unique per region. null generates <name>-<hash>."

  validation {
    condition     = var.cluster_endpoint_dns_label == null ? true : can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.cluster_endpoint_dns_label))
    error_message = "cluster_endpoint_dns_label must be 3-63 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "key_vault" {
  type = object({
    name             = optional(string)
    network_access   = optional(string, "Public")
    admin_object_ids = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "Key Vault holding the join tokens, the CA set and the generated SSH key. Put the principal that applies the module in admin_object_ids: it writes the secrets. After a destroy, Azure keeps the vault soft-deleted for 90 days, and the next apply recovers it with its secrets."

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
    enabled              = optional(bool, true)
    retention_days       = optional(number, 30)
    replication_type     = optional(string, "LRS")
    storage_account_name = optional(string)
  })
  default     = {}
  nullable    = false
  description = "Hourly upload of each new etcd snapshot from every server to a private storage account of its own, with the server identity, under <name>/<server>/<file>. Blob versioning and soft delete are on, and a lifecycle rule deletes snapshots after retention_days. Only the node subnet reaches the account; with existing_vnet, that subnet needs the Microsoft.Storage service endpoint. The account name derives from tags.Owner and name unless storage_account_name is set."

  validation {
    condition     = var.etcd_backup.retention_days >= 1 && var.etcd_backup.retention_days <= 365
    error_message = "etcd_backup.retention_days must be between 1 and 365."
  }
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.etcd_backup.replication_type)
    error_message = "etcd_backup.replication_type must be LRS, ZRS, GRS or GZRS."
  }
  validation {
    condition     = var.etcd_backup.storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.etcd_backup.storage_account_name))
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
    enabled                   = optional(bool, true)
    oidc_storage_account_name = optional(string)
    overrides = optional(object({
      external_dns = optional(object({
        enabled      = optional(bool)
        dns_zone_ids = optional(list(string), [])
      }), {})
      cert_manager = optional(object({
        enabled      = optional(bool)
        dns_zone_ids = optional(list(string), [])
      }), {})
    }), {})
  })
  default     = {}
  nullable    = false
  description = "Workload identities for external_dns and cert_manager, and the storage account that publishes the cluster's OIDC issuer. Set overrides.<identity>.enabled to turn one on or off. Set dns_zone_ids to grant it DNS Zone Contributor on those zones."

  validation {
    condition     = var.workload_identity.oidc_storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.workload_identity.oidc_storage_account_name))
    error_message = "workload_identity.oidc_storage_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "blob_csi" {
  type = object({
    enabled                   = optional(bool, false)
    create_storage_account    = optional(bool, true)
    storage_account_name      = optional(string)
    containers                = optional(list(string), [])
    network_access            = optional(string, "NodeSubnet")
    extra_subnet_ids          = optional(list(string), [])
    shared_access_key_enabled = optional(bool, false)
  })
  default     = {}
  nullable    = false
  description = "Blob storage for the blob CSI driver. Default: off. The module creates the storage account, the agent identity grant and the private containers. The README section \"Storage\" explains each field."

  validation {
    condition     = contains(["NodeSubnet", "Public"], var.blob_csi.network_access)
    error_message = "blob_csi.network_access must be one of: NodeSubnet, Public."
  }
  validation {
    condition     = var.blob_csi.storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.blob_csi.storage_account_name))
    error_message = "blob_csi.storage_account_name must be 3-24 lowercase letters and digits."
  }
  validation {
    condition     = alltrue([for name in var.blob_csi.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name))])
    error_message = "blob_csi.containers names must be 3-63 lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "entra_oidc" {
  type = object({
    enabled                = optional(bool, false)
    client_id              = optional(string)
    issuer_url             = optional(string)
    username_claim         = optional(string, "oid")
    groups_claim           = optional(string, "groups")
    username_prefix        = optional(string)
    admin_group_object_ids = optional(list(string), [])
    admin_object_ids       = optional(list(string), [])
    reader_object_ids      = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "Microsoft Entra ID as the API server's OIDC provider, for kubectl through kubelogin. client_id is an app registration you own, with token version 2 and group claims; issuer_url defaults to the tenant's v2 endpoint in azure_cloud. The username claim is oid, present in user and service principal tokens alike. Servers apply a ClusterRoleBinding to cluster-admin for admin_group_object_ids and admin_object_ids, and read-only bindings for reader_object_ids, before the first node joins. The README section \"Access\" lists what the app registration needs."

  validation {
    condition     = !var.entra_oidc.enabled || var.entra_oidc.client_id != null
    error_message = "entra_oidc.client_id is required when entra_oidc.enabled is true."
  }
}

variable "kube_exec_login_mode" {
  type        = string
  default     = "azurecli"
  description = "kubelogin --login mode in kube_exec, used with entra_oidc. azurecli reuses your az session; use spn, msi or workloadidentity in CI."

  validation {
    condition     = contains(["devicecode", "interactive", "spn", "ropc", "msi", "azurecli", "azd", "workloadidentity", "azurepipelines"], var.kube_exec_login_mode)
    error_message = "kube_exec_login_mode must be a kubelogin login mode: devicecode, interactive, spn, ropc, msi, azurecli, azd, workloadidentity, azurepipelines."
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
