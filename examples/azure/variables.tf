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

variable "cni_vm_size" {
  type        = string
  default     = "Standard_D4s_v5"
  description = "VM size of the kube-ovn node. ovn-central and kube-ovn-controller need about 2 vCPUs and 3 GB on it."
}

variable "cni" {
  type        = string
  default     = "kube-ovn"
  description = "CNI profile of the stack: cilium, kube-ovn or canal."
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
