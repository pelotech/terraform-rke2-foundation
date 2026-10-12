variable "name" {
  type        = string
  default     = "rke2-dev"
  description = "Cluster name and base of every resource name."
}

variable "location" {
  type        = string
  default     = "usgovvirginia"
  description = "Azure region."
}

variable "azure_cloud" {
  type        = string
  default     = "usgovernment"
  description = "Azure cloud for both the azurerm provider and the stack: public or usgovernment."
}

variable "server_vm_size" {
  type        = string
  default     = "Standard_D4s_v5"
  description = "VM size of the three server nodes."
}

variable "agent_vm_size" {
  type        = string
  default     = "Standard_D4s_v5"
  description = "VM size of the general agent pool."
}

variable "cni" {
  type = object({
    name      = string
    node_pool = optional(object({ vm_size = string }))
  })
  default     = { name = "kube-ovn", node_pool = { vm_size = "Standard_D4s_v5" } }
  description = "CNI of the stack: cilium, kube-ovn or canal. kube-ovn needs node_pool; ovn-central and kube-ovn-controller need about 2 vCPUs and 3 GB on that node."
}

variable "storage_account_prefix" {
  type        = string
  description = "Prefix of the OIDC issuer and etcd snapshot storage account names, which must be unique across Azure: 3-20 lowercase letters and digits. The module appends oidc and etcd."

  validation {
    condition     = can(regex("^[a-z0-9]{3,20}$", var.storage_account_prefix))
    error_message = "storage_account_prefix must be 3-20 lowercase letters and digits."
  }
}

variable "authorized_ip_ranges" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API server: the egress address of the host that applies this example, at least."
}

variable "key_vault_admin_object_ids" {
  type        = list(string)
  description = "Entra object ids that may write the Key Vault secrets. Include the principal that applies this example."
}

variable "tags" {
  type        = map(string)
  default     = { Owner = "pelotech", Environment = "dev" }
  description = "Tags for every resource. Owner seeds the storage account names."
}

variable "install_disk_csi" {
  type        = bool
  default     = true
  description = "Installs the Azure disk CSI driver so the smoke test can bind a PVC."
}

variable "disk_csi_chart_version" {
  # renovate: datasource=helm depName=azuredisk-csi-driver registryUrl=https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/charts
  type        = string
  default     = "v1.30.10"
  description = "azuredisk-csi-driver chart version."
}
