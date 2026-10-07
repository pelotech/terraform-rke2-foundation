variable "name" {
  type        = string
  description = "Cluster name. It prefixes the CA common names and names the kubeconfig context."
}

variable "rke2_version" {
  type        = string
  description = "RKE2 release to install, v1.36.0+rke2r1 or newer, for example v1.36.5+rke2r1. Passed to the install script as INSTALL_RKE2_VERSION."

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+\\+rke2r\\d+$", var.rke2_version))
    error_message = "rke2_version must be a full RKE2 release, for example v1.36.5+rke2r1."
  }

  validation {
    condition     = try(tonumber(regex("^v1\\.(\\d+)\\.", var.rke2_version)[0]) >= 36, false)
    error_message = "rke2_version must be v1.36.0+rke2r1 or newer: the module sets ingress-controller, which older releases do not know."
  }
}

variable "registration_address" {
  type        = string
  description = "Host or IP every node joins through on port 9345, the fixed registration address. Always part of tls-san."
}

variable "api_server_url" {
  type        = string
  default     = null
  description = "API server URL in the admin kubeconfig. null uses https://<registration_address>:6443."
}

variable "tls_sans" {
  type        = list(string)
  default     = []
  description = "Extra Subject Alternative Names for the API server certificate, for example a public FQDN."
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service CIDR, the RKE2 service-cidr."
}

variable "pod_cidr" {
  type        = string
  description = "Pod CIDR, the RKE2 cluster-cidr."
}

variable "cluster_dns" {
  type        = string
  description = "Cluster DNS service IP inside service_cidr, the RKE2 cluster-dns."
}

variable "cni" {
  type        = string
  default     = "none"
  description = "RKE2 cni value: none for a CNI installed afterwards, or a bundled one: canal, cilium or calico."

  validation {
    condition     = contains(["none", "canal", "cilium", "calico"], var.cni)
    error_message = "cni must be one of: none, canal, cilium, calico."
  }
}

variable "disable_kube_proxy" {
  type        = bool
  default     = false
  description = "Sets disable-kube-proxy, for a CNI that replaces kube-proxy."
}

variable "cloud_provider_name" {
  type        = string
  default     = null
  description = "RKE2 cloud-provider-name, for example external. Setting it also disables the RKE2 default cloud controller. null keeps that controller."
}

variable "cis_profile" {
  type        = bool
  default     = false
  description = "Sets profile: cis and performs the host prerequisites before RKE2 starts: the etcd user and the CIS sysctl file."
}

variable "secrets_encryption" {
  type        = bool
  default     = true
  description = "Sets secrets-encryption, RKE2's encryption of Secrets at rest in etcd."
}

variable "disable_components" {
  type        = list(string)
  default     = []
  description = "Packaged components RKE2 must not deploy: rke2-coredns, rke2-metrics-server, rke2-snapshot-controller, rke2-snapshot-controller-crd, rke2-snapshot-validation-webhook, and from v1.37 rke2-security-responder and rke2-gateway-api-crd. The ingress is ingress_controller."

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

variable "server_labels" {
  type        = map(string)
  default     = {}
  description = "Node labels for every server."
}

variable "server_taints" {
  type        = list(string)
  default     = ["CriticalAddonsOnly=true:NoSchedule"]
  description = "Node taints for every server as key=value:Effect strings. Empty makes servers schedulable."

  validation {
    condition     = alltrue([for t in var.server_taints : can(regex("^[^=:]+=[^:]*:(NoSchedule|PreferNoSchedule|NoExecute)$", t))])
    error_message = "server_taints entries must look like key=value:NoSchedule, key=value:PreferNoSchedule or key=value:NoExecute."
  }
}

variable "kube_apiserver_args" {
  type        = list(string)
  default     = []
  description = "kube-apiserver-arg entries, as flag=value strings."
}

variable "kube_controller_manager_args" {
  type        = list(string)
  default     = []
  description = "kube-controller-manager-arg entries, as flag=value strings."
}

variable "kubelet_args" {
  type        = list(string)
  default     = []
  description = "kubelet-arg entries for every node, as flag=value strings."
}

variable "extra_server_config" {
  type        = any
  default     = {}
  description = "RKE2 server config keys merged last into config.yaml. They override the keys the module sets."

  validation {
    condition     = can(keys(var.extra_server_config))
    error_message = "extra_server_config must be a map or object of RKE2 config keys."
  }
}

variable "extra_agent_config" {
  type        = any
  default     = {}
  description = "RKE2 agent config keys merged last into every agent's config.yaml. They override the keys the module sets."

  validation {
    condition     = can(keys(var.extra_agent_config))
    error_message = "extra_agent_config must be a map or object of RKE2 config keys."
  }
}

variable "agent_pools" {
  type = map(object({
    labels       = optional(map(string), {})
    taints       = optional(list(string), [])
    kubelet_args = optional(list(string), [])
  }))
  default     = {}
  description = "Agent pools to render cloud-init for, keyed by pool name. Taints are key=value:Effect strings."

  validation {
    condition     = alltrue([for pool in values(var.agent_pools) : alltrue([for t in pool.taints : can(regex("^[^=:]+=[^:]*:(NoSchedule|PreferNoSchedule|NoExecute)$", t))])])
    error_message = "agent_pools taints must look like key=value:NoSchedule, key=value:PreferNoSchedule or key=value:NoExecute."
  }
}

variable "server_manifests" {
  type        = map(string)
  default     = {}
  description = "Manifests every server writes to /var/lib/rancher/rke2/server/manifests before RKE2 starts, file name to YAML."
}

variable "fetch_secrets_scripts" {
  type = object({
    server = string
    agent  = string
  })
  description = "Shell each role sources as root. It must define fetch NAME PATH, which writes that secret to <SECRET_DIR>/<PATH>; bootstrap.sh calls it for every entry of server_secret_paths or agent_secret_paths."
}

variable "post_bootstrap_script" {
  type        = string
  default     = ""
  description = "Shell every server runs once the API answers /readyz, with KUBECONFIG set and kubectl on PATH. Empty runs nothing."
}

variable "bootstrap_wait_seconds" {
  type        = number
  default     = 90
  description = "How long server zero waits for the registration address before it bootstraps a new cluster. Other servers and agents wait without limit."

  validation {
    condition     = var.bootstrap_wait_seconds >= 10
    error_message = "bootstrap_wait_seconds must be at least 10."
  }
}

variable "certificate_renewal" {
  type        = bool
  default     = true
  description = "Renews node certificates on the node itself. A daily timer runs rke2 certificate check; when a certificate is inside RKE2's renewal window, an agent restarts rke2-agent, and a server rotates its keys with rke2 certificate rotate and restarts, one server at a time through a Lease in kube-system."
}

variable "disable_firewalld" {
  type        = bool
  default     = true
  description = "Stops and disables firewalld when the image ships it, as RKE2 documents it as incompatible with its networking. Set false on an image whose firewalld rules allow the RKE2 ports."
}

variable "etcd_disk_device" {
  type        = string
  default     = null
  description = "Block device for the etcd directory of a server, for example /dev/disk/azure/scsi1/lun0. bootstrap.sh waits for it, formats it with XFS when it carries no filesystem, and mounts it on the server db directory before RKE2 starts. null keeps etcd on the root disk."
}

variable "put_snapshot_script" {
  type        = string
  default     = ""
  description = "Shell every server sources as root. It must define put_snapshot PATH FILE, which stores FILE at PATH outside the node. With it, an hourly timer uploads each new etcd snapshot once. Empty installs no timer."
}

variable "install_script_url" {
  type        = string
  default     = "https://get.rke2.io"
  description = "URL of the RKE2 install script. Point it at a mirror in restricted networks."
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
