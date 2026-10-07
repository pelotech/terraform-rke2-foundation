variable "registration_address" {
  type        = string
  description = "Address of the haproxy VM; run.sh fills it in."
}

variable "cni" {
  type        = string
  default     = "kube-ovn"
  description = "Profile to render: cilium or kube-ovn."

  validation {
    condition     = contains(["cilium", "kube-ovn"], var.cni)
    error_message = "cni must be cilium or kube-ovn."
  }
}

variable "rke2_version" {
  # renovate: datasource=github-releases depName=rancher/rke2 versioning=regex:^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\+rke2r(?<build>\d+)$
  type        = string
  default     = "v1.37.1+rke2r1"
  description = "RKE2 release to install on the VMs."
}
