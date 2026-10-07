name        = "platformdev"
location    = "usgovvirginia"
azure_cloud = "usgovernment"
tags        = { Owner = "acme", Environment = "test" }
servers     = { vm_size = "Standard_D4s_v5" }
agent_pools = { general = { vm_size = "Standard_D4s_v5" } }
