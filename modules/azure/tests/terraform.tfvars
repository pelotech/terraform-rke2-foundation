name                = "platformdev"
location            = "usgovvirginia"
azure_cloud         = "usgovernment"
tags                = { Owner = "acme", Environment = "test" }
resource_group      = { name = "rg-platformdev", create = true }
node_resource_group = { name = "rg-platformdev-nodes", create = true }
network             = { create = {} }
cni                 = { name = "cilium" }
cluster_endpoint    = { public = true, authorized_ip_ranges = ["203.0.113.0/24"] }
key_vault           = { admin_object_ids = ["00000000-0000-0000-0000-000000000003"] }
entra_oidc          = null
workload_identity   = { storage_account_name = "acmeplatformdevoidc", external_dns = {}, cert_manager = {} }
etcd_backup         = { storage_account_name = "acmeplatformdevetcd" }
blob_csi            = null
servers             = { vm_size = "Standard_D4s_v5" }
agent_pools         = { general = { vm_size = "Standard_D4s_v5" } }
