name                 = "platformdev"
rke2_version         = "v1.36.5+rke2r1"
registration_address = "10.0.0.4"
service_cidr         = "10.96.0.0/16"
pod_cidr             = "10.244.0.0/16"
cluster_dns          = "10.96.0.10"
fetch_secrets_scripts = {
  server = "echo server"
  agent  = "echo agent"
}
