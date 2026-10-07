variable "cni" {
  type        = string
  description = "Profile: cilium or kube-ovn."
}

variable "endpoint" {
  type        = string
  description = "API server URL."
}

variable "ca" {
  type        = string
  description = "Base64 PEM of the server CA."
}

variable "cert" {
  type        = string
  description = "Base64 PEM of the admin client certificate."
}

variable "key" {
  type        = string
  sensitive   = true
  description = "Base64 PEM of the admin client key."
}

variable "cni_node_size" {
  type        = number
  description = "Nodes the poll waits for."
}

variable "cni_node_selector" {
  type        = string
  description = "Selector of those nodes."
}
