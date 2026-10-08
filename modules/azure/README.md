# modules/azure

An RKE2 cluster on Azure, with the same contract outputs as terraform-azure-foundation, the AKS foundation. It creates:

- a VNet with a node subnet and a NAT Gateway
- an internal load balancer on 6443 and 9345, the registration address every node joins through, and a
  public one on 6443 when the API server is public
- three server VMs, and one scale set per agent pool
- a Key Vault with the join tokens and the custom CA set the servers adopt on first start
- cloud-provider-azure, installed by RKE2 from a manifest the servers write before they start
- an OIDC issuer on a storage account, and the workload identities for external-dns and cert-manager
- optional blob storage for the blob CSI driver

The helm provider and the cni-bootstrap module use its outputs. See "Install the CNI".

## Prerequisites

- Terraform 1.9 or later, the azurerm provider 5.0 or later and the tls provider 4.0 or later.
- The principal that applies the module in `key_vault.admin_object_ids`: it writes the secrets.
- Outbound internet from the node subnet for `https://get.rke2.io`, the RKE2 release and the
  cloud-provider-azure chart, or `install_script_url` pointed at a mirror.
- `kubectl` on the host that applies cni-bootstrap.
- A marketplace image accepted in your subscription. See "Node image".

## Quick start

```hcl
provider "azurerm" {
  environment = "usgovernment"
  features {}
}

module "stack" {
  source      = "github.com/pelotech/terraform-rke2-foundation//modules/azure?ref=<release tag>"
  name        = "platform-dev"
  location    = "usgovvirginia"
  azure_cloud = "usgovernment"
  cni         = "cilium"
  servers     = { vm_size = "Standard_D4s_v5" }
  agent_pools = {
    general = { vm_size = "Standard_D8s_v5", node_count = 2, min_count = 2, max_count = 10 }
  }
  key_vault = { admin_object_ids = [var.platform_admins_group_id] }
  workload_identity = {
    overrides = {
      external_dns = { dns_zone_ids = [var.dns_zone_id] }
      cert_manager = { dns_zone_ids = [var.dns_zone_id] }
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.stack.cluster_endpoint
    cluster_ca_certificate = base64decode(module.stack.cluster_ca_certificate)
    client_certificate     = base64decode(module.stack.admin_client_certificate)
    client_key             = base64decode(module.stack.admin_client_key)
  }
}
```

## Install the CNI

Apply cni-bootstrap after this module. It needs a cni-bootstrap release with the `distribution`,
`client_certificate`, `client_key` and `k8s_service_port` inputs:

```hcl
module "cni" {
  source                  = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=<release tag>"
  cloud                   = module.stack.cloud
  distribution            = module.stack.distribution
  cni                     = "cilium"
  cluster_endpoint        = module.stack.cluster_endpoint
  cluster_ca_certificate  = module.stack.cluster_ca_certificate
  client_certificate      = module.stack.admin_client_certificate
  client_key              = module.stack.admin_client_key
  k8s_service_host        = module.stack.cluster_api_host
  k8s_service_port        = module.stack.cluster_api_port
  service_cidr            = module.stack.cluster_service_cidr
  pod_cidr                = module.stack.cluster_pod_cidr
  wait_for_nodes_count    = module.stack.cni_node_size
  wait_for_nodes_selector = module.stack.cni_node_selector
}
```

- For kube-ovn, set `cni = "kube-ovn"` on this module and `cni = "kube-ovn-v2"` on cni-bootstrap.
- With `distribution = "rke2"`, cni-bootstrap turns Cilium's kube-proxy replacement on and skips the AKS
  bring-your-own-CNI setting. This module turns kube-proxy off for the cilium profile.
- The node poll waits for every server with cilium, which is what gates Helm on the API being ready.

## Choose a CNI

| `cni`              | RKE2 `cni` | kube-proxy | CNI node pool                                 | cni-bootstrap `cni` |
| ------------------ | ---------- | ---------- | --------------------------------------------- | ------------------- |
| `cilium` (default) | `none`     | off        | none                                          | `cilium`            |
| `kube-ovn`         | `none`     | on         | 1 node, label `kube-ovn/role=master`, tainted | `kube-ovn-v2`       |
| `canal`            | `canal`    | on         | none                                          | not used            |

Canal is the only CNI RKE2 rebuilds for FIPS. The AKS stack already runs Cilium and kube-ovn on
FIPS-enabled nodes; apply the same judgement here.

## Servers and bootstrap

- Servers carry `CriticalAddonsOnly=true:NoSchedule`, like the AKS system pool, unless
  `servers.schedulable` is true. RKE2 labels them `node-role.kubernetes.io/control-plane=true`.
- Server node 0 waits `servers.bootstrap_wait_seconds` for the registration address. If nothing answers,
  it starts a new cluster. Otherwise it joins, which is what a replaced server node 0 does.
- The bootstrap fetches the CA set and the tokens from the Key Vault with the server identity. It writes
  them where RKE2 reads them. It installs the pinned release and starts the service. Role assignments can
  take minutes to propagate, so the fetch retries for fifteen minutes.
- Terraform ignores a changed cloud-init on server nodes, so a changed setting never replaces all three at
  once. To replace one, follow the docs section "Replace a server node".

## Agent pools

- One scale set per `agent_pools` entry. `node_count` is the initial size and Terraform never changes
  the size of an existing pool.
- Set `min_count` and `max_count` to tag the pool for cluster-autoscaler. The GitOps layer runs the
  autoscaler on the server nodes with the server identity: `useManagedIdentityExtension = true`,
  `userAssignedIdentityID = server_identity_client_id` and `vmType = vmss`. Karpenter does not apply: its
  Azure provider supports AKS only.
- A changed cloud-init, for example a new `rke2_version`, applies to new instances only. To roll a pool,
  follow the docs section "Roll an agent pool", or reimage the instances as in "Reimage an agent node".
- For kube-ovn, `cni_node_pool` adds the one-node `cni` pool. Set `enabled = false`, then `true`, to
  recycle it, and raise cni-bootstrap `bootstrap_generation` in the same apply.
  Size that node for ovn-central and kube-ovn-controller together: cni-bootstrap's defaults request about
  2 vCPUs and 3 GB on it, so keep the servers' size or larger.

## Node image

- `image` is one marketplace image for every node. The default is one pinned build of RHEL 10.2, so that every
  node runs the same image. To move to a new build, set `image.version`, then replace the servers and roll the
  pools. Azure Linux is not on the RKE2 support matrix.
- Cloud-init stops firewalld on the node unless `disable_firewalld = false`.
- On RHEL 10, cloud-init installs `kernel-modules-extra` for the running kernel from the Red Hat Update
  Infrastructure before RKE2 starts. The Azure Marketplace image does not include the iptables modules that
  kube-proxy and kube-ovn need. A custom image must include that package, or the node must have access to a
  repository that has it.
- With SELinux on, the bootstrap labels the host directories that the kube-ovn pods write. The kube-ovn profile
  supplies the list. [docs/BOOTSTRAP.md](../../docs/BOOTSTRAP.md) has the details.

## Networking

| Setup                      | Inputs                                                          | Egress              |
| -------------------------- | --------------------------------------------------------------- | ------------------- |
| Created VNet               | defaults                                                        | NAT Gateway, always |
| Existing VNet              | `existing_vnet = { vnet_id, node_subnet_id, api_private_ip }`   | yours               |

- The internal API address is the node subnet's last usable address, or `existing_vnet.api_private_ip`.
- The `nat_gateway_public_ips` output lists the gateway addresses. Use them in allow lists.
- `private_endpoints` creates one private endpoint in the node subnet for each target resource.
- A network security group sits on every node NIC. cloud-provider-azure adds the rules for LoadBalancer
  Services there; the module adds only the API server rule for a public endpoint.

## Access

- With `entra_oidc` on, people and pipelines sign in through Entra ID with kubelogin, from the
  `kubeconfig_entra` output, which holds no secret. The admin client certificate in the `kubeconfig` output
  is the break-glass path. Without `entra_oidc`, the certificate is the only credential. The docs section
  "Get access" has the steps.
- For SSH from the VNet, read the secret `ssh-private-key` from the Key Vault if you did not supply a key. The
  user is `admin_username`.
- By default, the API server accepts connections from the internet. To accept only some addresses, set
  `cluster_endpoint_authorized_ip_ranges`. For a private cluster, set
  `cluster_endpoint_public_access = false`.
- `entra_oidc` makes Entra ID the API server's OIDC provider and fills `kube_exec` with the kubelogin
  block the AKS foundation emits, with `--server-id` set to your app registration. The app registration
  needs: token version 2, so the issuer is the tenant's v2.0 endpoint; `SecurityGroup` in its group
  membership claims; a scope that pre-authorizes the Azure CLI client, so `--login azurecli` gets a token
  without a consent prompt; and a service principal. One app serves every RKE2 cluster in the tenant.
- The username claim is `oid`, which user and service principal tokens both carry. Servers apply
  `entra-access.yaml` before the first node joins: cluster-admin for `admin_group_object_ids` and
  `admin_object_ids`, and view plus the kube-system Secrets of Helm releases for `reader_object_ids`, so
  a plan identity can refresh them. Entra omits the `groups` claim above about 200 groups per user.

## Workload identity

The module uses Microsoft Entra Workload ID for every identity. The cluster publishes its OIDC discovery
document and JWKS from the issuer storage account's static website; each server uploads them once the
API answers. For each controller, the GitOps layer must:

1. Set the service account annotation `azure.workload.identity/client-id` to the `<identity>_client_id` output.
2. Set the label `azure.workload.identity/use: "true"` on the pod template.

DNS grants work as on AKS: list each zone in `dns_zone_ids`, or leave it empty and use the
`<identity>_principal_id` output to assign roles yourself.

## Storage

- The disk CSI controller runs on the server nodes. It creates disks in the node resource group with the
  server identity that the cloud config names. The agent identity has Contributor on that group for the
  CSI node plugin.
- `blob_csi.enabled = true` creates a storage account, a Storage Blob Data Contributor grant for the agent
  identity and one private container per name in `blob_csi.containers`, with the same `network_access`,
  `extra_subnet_ids` and `shared_access_key_enabled` fields as the AKS foundation.

## Upgrades

`rke2_version` pins the release each node installs. A change applies to new nodes only. The docs section
"Upgrade RKE2" in [docs/OPERATIONS.md](../../docs/OPERATIONS.md) has the order, the etcd snapshot step and what
a chart or image change needs.

## Hardening

- `cis_profile = true` runs RKE2 with `profile: cis`, after cloud-init creates the etcd user and installs
  the CIS sysctl file.
- `secrets_encryption` is on by default.
- A FIPS image: a marketplace image with its purchase plan in `image.plan`, after you accept its terms in
  your subscription. The module takes no Compute Gallery image yet. The docs section "Build a hardened
  image" lists the steps.
- `ingress_controller = "none"` and `disable_components` leave the packaged ingress and snapshot
  controller out by default, as the GitOps layer provides both.
- `certificate_renewal` keeps a daily timer on every node that renews RKE2's certificates before they
  expire; see the docs section "Rotate certificates and tokens".
- `etcd_backup` runs an hourly timer that uploads each new etcd snapshot to a private storage account; see
  the docs section "Back up etcd".

## What stays in state

The CA private keys, the join tokens, the admin client key, the generated SSH key and the kubeconfig
are in the Terraform state, marked sensitive. Protect the state as you would the vault.

## Known issues

- On a first apply, Key Vault role grants can take some minutes to become active. If the apply fails
  with 403, run it again.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.0.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.0.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bootstrap"></a> [bootstrap](#module\_bootstrap) | ../bootstrap | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_federated_identity_credential.workload](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_secret.node](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.ssh_private_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_lb.api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb) | resource |
| [azurerm_lb.api_public](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb) | resource |
| [azurerm_lb_backend_address_pool.api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_backend_address_pool) | resource |
| [azurerm_lb_backend_address_pool.api_public](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_backend_address_pool) | resource |
| [azurerm_lb_probe.api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_probe) | resource |
| [azurerm_lb_rule.api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_rule) | resource |
| [azurerm_linux_virtual_machine.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_linux_virtual_machine_scale_set.agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine_scale_set) | resource |
| [azurerm_managed_disk.etcd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_disk) | resource |
| [azurerm_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_network_interface.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_backend_address_pool_association.server_api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_backend_address_pool_association) | resource |
| [azurerm_network_interface_backend_address_pool_association.server_api_public](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_backend_address_pool_association) | resource |
| [azurerm_network_interface_security_group_association.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_security_group_association) | resource |
| [azurerm_network_security_group.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_rule.api_server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_private_endpoint.node_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_public_ip.api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_public_ip.nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.external_dns_zone_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.key_vault_admin](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.workload_dns_zone](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.blob_csi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_account.etcd_backup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_account.oidc](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_account_network_rules.blob_csi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_network_rules) | resource |
| [azurerm_storage_account_network_rules.etcd_backup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_network_rules) | resource |
| [azurerm_storage_account_static_website.oidc](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_static_website) | resource |
| [azurerm_storage_container.blob_csi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_container.etcd_backup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_management_policy.etcd_backup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_management_policy) | resource |
| [azurerm_subnet.database](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_user_assigned_identity.agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.workload](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_virtual_machine_data_disk_attachment.etcd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_data_disk_attachment) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [tls_private_key.ssh](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_agent_pools"></a> [agent\_pools](#input\_agent\_pools) | Agent scale sets, keyed by pool name. node\_count is the initial size; set min\_count and max\_count to tag the pool for cluster-autoscaler, which then owns the size. The README section "Agent pools" explains the rest. | <pre>map(object({<br/>    vm_size         = string<br/>    node_count      = optional(number, 1)<br/>    min_count       = optional(number)<br/>    max_count       = optional(number)<br/>    zones           = optional(list(string), ["1", "2", "3"])<br/>    os_disk_size_gb = optional(number, 100)<br/>    os_disk_type    = optional(string, "Premium_LRS")<br/>    labels          = optional(map(string), {})<br/>    taints = optional(map(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region for every resource, for example usgovvirginia. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the cluster. It is the base of every generated resource name and of the node hostnames. | `string` | n/a | yes |
| <a name="input_servers"></a> [servers](#input\_servers) | Control plane VMs. count must be odd. Servers carry the CriticalAddonsOnly taint unless schedulable is true. zones round-robin across the servers; empty means no zone. etcd\_disk is a Premium SSD v2 data disk per server for the etcd directory, with no host cache, replaced together with its VM; iops and mbps start at the 3000 and 125 the SKU includes. | <pre>object({<br/>    vm_size                = string<br/>    count                  = optional(number, 3)<br/>    zones                  = optional(list(string), ["1", "2", "3"])<br/>    os_disk_size_gb        = optional(number, 100)<br/>    os_disk_type           = optional(string, "Premium_LRS")<br/>    labels                 = optional(map(string), {})<br/>    schedulable            = optional(bool, false)<br/>    bootstrap_wait_seconds = optional(number, 90)<br/>    etcd_disk = optional(object({<br/>      enabled = optional(bool, true)<br/>      size_gb = optional(number, 64)<br/>      iops    = optional(number, 3000)<br/>      mbps    = optional(number, 125)<br/>    }), {})<br/>  })</pre> | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Linux admin user on every node, with ssh\_public\_key. | `string` | `"rke2admin"` | no |
| <a name="input_azure_cloud"></a> [azure\_cloud](#input\_azure\_cloud) | Azure cloud: public or usgovernment. It selects the cloud provider environment, the Key Vault audience and the kubelogin environment. Set it to the same cloud as your azurerm provider. | `string` | `"public"` | no |
| <a name="input_blob_csi"></a> [blob\_csi](#input\_blob\_csi) | Blob storage for the blob CSI driver. Default: off. The module creates the storage account, the agent identity grant and the private containers. The README section "Storage" explains each field. | <pre>object({<br/>    enabled                   = optional(bool, false)<br/>    create_storage_account    = optional(bool, true)<br/>    storage_account_name      = optional(string)<br/>    containers                = optional(list(string), [])<br/>    network_access            = optional(string, "NodeSubnet")<br/>    extra_subnet_ids          = optional(list(string), [])<br/>    shared_access_key_enabled = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_certificate_renewal"></a> [certificate\_renewal](#input\_certificate\_renewal) | Renews node certificates on the nodes themselves with a daily timer; see the bootstrap module. Off, the operator renews by restart or replacement. | `bool` | `true` | no |
| <a name="input_cis_profile"></a> [cis\_profile](#input\_cis\_profile) | Runs RKE2 with profile cis: the CIS host prerequisites, restricted Pod Security Admission and default network policies. | `bool` | `false` | no |
| <a name="input_cloud_provider_chart_version"></a> [cloud\_provider\_chart\_version](#input\_cloud\_provider\_chart\_version) | cloud-provider-azure chart version. Keep its MAJOR.MINOR equal to the Kubernetes minor in rke2\_version, or set cloud\_provider\_image\_tag when the chart lags Kubernetes. | `string` | `"1.36.0"` | no |
| <a name="input_cloud_provider_image_tag"></a> [cloud\_provider\_image\_tag](#input\_cloud\_provider\_image\_tag) | Image tag of the cloud-provider-azure controller and node manager, whose minor must equal the Kubernetes minor. null keeps the chart's own tag. Set it when the chart lags Kubernetes. | `string` | `"v1.37.0"` | no |
| <a name="input_cluster_endpoint_authorized_ip_ranges"></a> [cluster\_endpoint\_authorized\_ip\_ranges](#input\_cluster\_endpoint\_authorized\_ip\_ranges) | CIDRs allowed to reach the public API server. Empty allows all. | `list(string)` | `[]` | no |
| <a name="input_cluster_endpoint_dns_label"></a> [cluster\_endpoint\_dns\_label](#input\_cluster\_endpoint\_dns\_label) | DNS label of the public API address, unique per region. null generates <name>-<hash>. | `string` | `null` | no |
| <a name="input_cluster_endpoint_public_access"></a> [cluster\_endpoint\_public\_access](#input\_cluster\_endpoint\_public\_access) | Adds a public load balancer in front of the API server. false keeps only the internal one, which needs VNet connectivity to apply cni-bootstrap. | `bool` | `true` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | CNI to run: cilium, kube-ovn or canal. cilium and kube-ovn set RKE2 cni none and cni-bootstrap installs the CNI; cilium also turns kube-proxy off. canal is the bundled, FIPS-rebuilt CNI. kube-ovn also creates the CNI node pool. | `string` | `"cilium"` | no |
| <a name="input_cni_node_pool"></a> [cni\_node\_pool](#input\_cni\_node\_pool) | Dedicated CNI pool, created for kube-ovn as the scale set named cni. vm\_size and zones default to the servers'. Set enabled = false, then true, to recycle the pool. | <pre>object({<br/>    enabled         = optional(bool, true)<br/>    vm_size         = optional(string)<br/>    zones           = optional(list(string))<br/>    node_count      = optional(number, 1)<br/>    os_disk_size_gb = optional(number, 100)<br/>    os_disk_type    = optional(string, "Premium_LRS")<br/>  })</pre> | `{}` | no |
| <a name="input_create_resource_group"></a> [create\_resource\_group](#input\_create\_resource\_group) | Creates the resource group. Set false to use an existing group named resource\_group\_name. | `bool` | `true` | no |
| <a name="input_disable_components"></a> [disable\_components](#input\_disable\_components) | Packaged RKE2 components not to deploy. Default: no snapshot controller, which the GitOps layer provides, as on AKS. The ingress is ingress\_controller. | `list(string)` | <pre>[<br/>  "rke2-snapshot-controller",<br/>  "rke2-snapshot-controller-crd",<br/>  "rke2-snapshot-validation-webhook"<br/>]</pre> | no |
| <a name="input_disable_firewalld"></a> [disable\_firewalld](#input\_disable\_firewalld) | Stops firewalld at bootstrap on images that ship it, such as RHEL. Set false on an image whose firewalld rules allow the RKE2 ports. | `bool` | `true` | no |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | Cluster DNS service IP inside service\_cidr. null uses the tenth address. | `string` | `null` | no |
| <a name="input_entra_oidc"></a> [entra\_oidc](#input\_entra\_oidc) | Microsoft Entra ID as the API server's OIDC provider, for kubectl through kubelogin. client\_id is an app registration you own, with token version 2 and group claims; issuer\_url defaults to the tenant's v2 endpoint in azure\_cloud. The username claim is oid, present in user and service principal tokens alike. Servers apply a ClusterRoleBinding to cluster-admin for admin\_group\_object\_ids and admin\_object\_ids, and read-only bindings for reader\_object\_ids, before the first node joins. The README section "Access" lists what the app registration needs. | <pre>object({<br/>    enabled                = optional(bool, false)<br/>    client_id              = optional(string)<br/>    issuer_url             = optional(string)<br/>    username_claim         = optional(string, "oid")<br/>    groups_claim           = optional(string, "groups")<br/>    username_prefix        = optional(string)<br/>    admin_group_object_ids = optional(list(string), [])<br/>    admin_object_ids       = optional(list(string), [])<br/>    reader_object_ids      = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_etcd_backup"></a> [etcd\_backup](#input\_etcd\_backup) | Hourly upload of each new etcd snapshot from every server to a private storage account of its own, with the server identity, under <name>/<server>/<file>. Blob versioning and soft delete are on, and a lifecycle rule deletes snapshots after retention\_days. Only the node subnet reaches the account; with existing\_vnet, that subnet needs the Microsoft.Storage service endpoint. The account name derives from tags.Owner and name unless storage\_account\_name is set. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    retention_days       = optional(number, 30)<br/>    replication_type     = optional(string, "LRS")<br/>    storage_account_name = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_existing_vnet"></a> [existing\_vnet](#input\_existing\_vnet) | Use an existing VNet and node subnet. The module then creates no network and no NAT Gateway, so the subnet must provide egress. api\_private\_ip is the static address of the API load balancer; null lets Azure pick one. | <pre>object({<br/>    vnet_id        = string<br/>    node_subnet_id = string<br/>    api_private_ip = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_extra_agent_config"></a> [extra\_agent\_config](#input\_extra\_agent\_config) | RKE2 agent config keys merged last into every agent's config.yaml. They override the module's keys. | `any` | `{}` | no |
| <a name="input_extra_server_config"></a> [extra\_server\_config](#input\_extra\_server\_config) | RKE2 server config keys merged last into every server's config.yaml. They override the module's keys. | `any` | `{}` | no |
| <a name="input_image"></a> [image](#input\_image) | Marketplace image for every node. Default: RHEL 10.2, generation 2, pinned to one build so every node runs the same image; bump the version on purpose, then replace the servers and roll the pools. Set plan for an image that needs purchase terms. | <pre>object({<br/>    publisher = optional(string, "RedHat")<br/>    offer     = optional(string, "RHEL")<br/>    sku       = optional(string, "10_2-gen2")<br/>    version   = optional(string, "10.2.2026080415")<br/>    plan = optional(object({<br/>      name      = string<br/>      product   = string<br/>      publisher = string<br/>    }))<br/>  })</pre> | `{}` | no |
| <a name="input_ingress_controller"></a> [ingress\_controller](#input\_ingress\_controller) | Packaged ingress controller: none, traefik or ingress-nginx. The GitOps layer provides the ingress, as on AKS, so the default is none. | `string` | `"none"` | no |
| <a name="input_key_vault"></a> [key\_vault](#input\_key\_vault) | Key Vault holding the join tokens, the CA set and the generated SSH key. Put the principal that applies the module in admin\_object\_ids: it writes the secrets. After a destroy, Azure keeps the vault soft-deleted for 90 days, and the next apply recovers it with its secrets. | <pre>object({<br/>    name             = optional(string)<br/>    network_access   = optional(string, "Public")<br/>    admin_object_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_kube_apiserver_args"></a> [kube\_apiserver\_args](#input\_kube\_apiserver\_args) | Extra kube-apiserver-arg entries, as flag=value strings, after the ones the module sets. | `list(string)` | `[]` | no |
| <a name="input_kube_controller_manager_args"></a> [kube\_controller\_manager\_args](#input\_kube\_controller\_manager\_args) | Extra kube-controller-manager-arg entries, as flag=value strings. | `list(string)` | `[]` | no |
| <a name="input_kube_exec_login_mode"></a> [kube\_exec\_login\_mode](#input\_kube\_exec\_login\_mode) | kubelogin --login mode in kube\_exec, used with entra\_oidc. azurecli reuses your az session; use spn, msi or workloadidentity in CI. | `string` | `"azurecli"` | no |
| <a name="input_kubelet_args"></a> [kubelet\_args](#input\_kubelet\_args) | kubelet-arg entries for every node, as flag=value strings. | `list(string)` | `[]` | no |
| <a name="input_nat_gateway"></a> [nat\_gateway](#input\_nat\_gateway) | NAT Gateway for node egress, created whenever the module creates the VNet. | <pre>object({<br/>    public_ip_count      = optional(number, 1)<br/>    idle_timeout_minutes = optional(number, 4)<br/>  })</pre> | `{}` | no |
| <a name="input_node_resource_group_name"></a> [node\_resource\_group\_name](#input\_node\_resource\_group\_name) | Resource group the module creates for the nodes and everything the cloud provider and CSI driver create. null generates rg-<name>-nodes. | `string` | `null` | no |
| <a name="input_pki"></a> [pki](#input\_pki) | Validity of the CA set and of the admin client certificate, which Terraform renews admin\_early\_renewal\_hours before it expires. | <pre>object({<br/>    ca_validity_hours         = optional(number, 87600)<br/>    admin_validity_hours      = optional(number, 8760)<br/>    admin_early_renewal_hours = optional(number, 720)<br/>  })</pre> | `{}` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Pod CIDR, the RKE2 cluster-cidr. Pass the cluster\_pod\_cidr output to cni-bootstrap so the CNI uses the same range. | `string` | `"10.244.0.0/16"` | no |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints in the node subnet, one for each target resource. You select the key names. Example subresource\_names: ["blob"], ["vault"], ["registry"]. | <pre>map(object({<br/>    resource_id          = string<br/>    subresource_names    = list(string)<br/>    private_dns_zone_ids = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group for the network, Key Vault, identities and load balancers. null generates rg-<name>. | `string` | `null` | no |
| <a name="input_rke2_version"></a> [rke2\_version](#input\_rke2\_version) | RKE2 release every node installs, v1.36.0+rke2r1 or newer. Changing it affects new nodes only; see the README section "Upgrades". | `string` | `"v1.37.1+rke2r1"` | no |
| <a name="input_secrets_encryption"></a> [secrets\_encryption](#input\_secrets\_encryption) | Encrypts Secrets at rest in etcd with RKE2's secrets-encryption. | `bool` | `true` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | Kubernetes service CIDR, with a prefix longer than /12. It must not overlap the VNet or pod\_cidr. | `string` | `"10.96.0.0/16"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | OpenSSH public key for admin\_username on every node. null generates an RSA key pair and stores the private key in the Key Vault as ssh-private-key. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. The Owner tag, when present, seeds the storage account names. | `map(string)` | `{}` | no |
| <a name="input_vnet"></a> [vnet](#input\_vnet) | VNet the module creates; ignored when existing\_vnet is set. Size node\_subnet\_cidr for the maximum node count plus private endpoints. The API load balancer takes the subnet's last usable address. | <pre>object({<br/>    cidr                 = optional(string, "10.0.0.0/16")<br/>    node_subnet_cidr     = optional(string, "10.0.0.0/22")<br/>    database_subnet_cidr = optional(string)<br/>    service_endpoints    = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_workload_identity"></a> [workload\_identity](#input\_workload\_identity) | Workload identities for external\_dns and cert\_manager, and the storage account that publishes the cluster's OIDC issuer. Set overrides.<identity>.enabled to turn one on or off. Set dns\_zone\_ids to grant it DNS Zone Contributor on those zones. | <pre>object({<br/>    enabled                   = optional(bool, true)<br/>    oidc_storage_account_name = optional(string)<br/>    overrides = optional(object({<br/>      external_dns = optional(object({<br/>        enabled      = optional(bool)<br/>        dns_zone_ids = optional(list(string), [])<br/>      }), {})<br/>      cert_manager = optional(object({<br/>        enabled      = optional(bool)<br/>        dns_zone_ids = optional(list(string), [])<br/>      }), {})<br/>    }), {})<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_client_certificate"></a> [admin\_client\_certificate](#output\_admin\_client\_certificate) | Base64 encoded PEM admin client certificate, system:admin in system:masters, for the helm provider's client\_certificate. |
| <a name="output_admin_client_key"></a> [admin\_client\_key](#output\_admin\_client\_key) | Base64 encoded PEM private key of the admin client certificate, for the helm provider's client\_key. |
| <a name="output_agent_identity_client_id"></a> [agent\_identity\_client\_id](#output\_agent\_identity\_client\_id) | Client ID of the agent identity, the kubelet identity the CSI drivers use. |
| <a name="output_agent_identity_id"></a> [agent\_identity\_id](#output\_agent\_identity\_id) | Resource ID of the agent identity. |
| <a name="output_agent_identity_principal_id"></a> [agent\_identity\_principal\_id](#output\_agent\_identity\_principal\_id) | Principal ID of the agent identity, for extra role assignments. |
| <a name="output_agent_pools_resolved"></a> [agent\_pools\_resolved](#output\_agent\_pools\_resolved) | Agent pools after adding the CNI pool, with taints as the key=value:Effect strings RKE2 receives. |
| <a name="output_agent_scale_set_ids"></a> [agent\_scale\_set\_ids](#output\_agent\_scale\_set\_ids) | Resource ID of each agent scale set, by pool name. |
| <a name="output_api_private_ip"></a> [api\_private\_ip](#output\_api\_private\_ip) | Internal address of the API server and the registration address every node joins through. |
| <a name="output_api_public_fqdn"></a> [api\_public\_fqdn](#output\_api\_public\_fqdn) | Public FQDN of the API server, null for a private cluster. |
| <a name="output_api_public_ip"></a> [api\_public\_ip](#output\_api\_public\_ip) | Public address of the API server, null for a private cluster. |
| <a name="output_blob_csi_container_names"></a> [blob\_csi\_container\_names](#output\_blob\_csi\_container\_names) | Names of the blob containers created in the blob CSI storage account, empty when none. |
| <a name="output_blob_csi_storage_account_id"></a> [blob\_csi\_storage\_account\_id](#output\_blob\_csi\_storage\_account\_id) | Resource ID of the blob CSI storage account, null when not created. |
| <a name="output_blob_csi_storage_account_name"></a> [blob\_csi\_storage\_account\_name](#output\_blob\_csi\_storage\_account\_name) | Name of the blob CSI storage account, null when not created. Use it as the storageAccount of a PersistentVolume. |
| <a name="output_cert_manager_client_id"></a> [cert\_manager\_client\_id](#output\_cert\_manager\_client\_id) | Client ID of the cert-manager workload identity, null when disabled. |
| <a name="output_cert_manager_identity_id"></a> [cert\_manager\_identity\_id](#output\_cert\_manager\_identity\_id) | Resource ID of the cert-manager workload identity, null when disabled. |
| <a name="output_cert_manager_principal_id"></a> [cert\_manager\_principal\_id](#output\_cert\_manager\_principal\_id) | Principal ID of the cert-manager workload identity, for role assignments you create yourself. |
| <a name="output_cloud"></a> [cloud](#output\_cloud) | Cloud this stack runs on. Pass it to cni-bootstrap cloud. |
| <a name="output_cloud_config_resolved"></a> [cloud\_config\_resolved](#output\_cloud\_config\_resolved) | cloud-provider-azure cloud config the servers write into the azure-cloud-config secret. |
| <a name="output_cluster_api_host"></a> [cluster\_api\_host](#output\_cluster\_api\_host) | Host for Cilium k8sServiceHost. Every RKE2 node runs a local API load balancer on 127.0.0.1:6443, so this is not the external host. |
| <a name="output_cluster_api_port"></a> [cluster\_api\_port](#output\_cluster\_api\_port) | Port for Cilium k8sServicePort, the RKE2 agent load balancer port. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64 encoded PEM of the CA that signs the API server certificate, known at plan time. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | API server URL for the helm provider and cni-bootstrap: the public FQDN, or the internal address for a private cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the cluster. |
| <a name="output_cluster_pod_cidr"></a> [cluster\_pod\_cidr](#output\_cluster\_pod\_cidr) | Pod CIDR, the RKE2 cluster-cidr. Pass it to cni-bootstrap pod\_cidr. |
| <a name="output_cluster_service_cidr"></a> [cluster\_service\_cidr](#output\_cluster\_service\_cidr) | Kubernetes service CIDR. Pass it to cni-bootstrap service\_cidr. |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | RKE2 release the nodes install. |
| <a name="output_cni_node_labels_resolved"></a> [cni\_node\_labels\_resolved](#output\_cni\_node\_labels\_resolved) | Labels of the CNI node pool. Set even when the pool is not created. |
| <a name="output_cni_node_pool_enabled"></a> [cni\_node\_pool\_enabled](#output\_cni\_node\_pool\_enabled) | Whether the CNI node pool is created. |
| <a name="output_cni_node_selector"></a> [cni\_node\_selector](#output\_cni\_node\_selector) | Label selector of those nodes. Pass it to cni-bootstrap wait\_for\_nodes\_selector. |
| <a name="output_cni_node_size"></a> [cni\_node\_size](#output\_cni\_node\_size) | Nodes cni-bootstrap waits for: the CNI pool size for kube-ovn, otherwise the server count, so Helm connects once the API is up. Pass it to cni-bootstrap wait\_for\_nodes\_count. |
| <a name="output_cni_node_taints_resolved"></a> [cni\_node\_taints\_resolved](#output\_cni\_node\_taints\_resolved) | Taints of the CNI node pool as key, value and effect objects. Set even when the pool is not created. |
| <a name="output_database_subnet_id"></a> [database\_subnet\_id](#output\_database\_subnet\_id) | ID of the database subnet, null unless vnet.database\_subnet\_cidr is set. |
| <a name="output_distribution"></a> [distribution](#output\_distribution) | Kubernetes distribution this stack runs. Pass it to cni-bootstrap distribution. |
| <a name="output_dns_service_ip_resolved"></a> [dns\_service\_ip\_resolved](#output\_dns\_service\_ip\_resolved) | Cluster DNS service IP after resolving dns\_service\_ip and service\_cidr. |
| <a name="output_etcd_backup_container_url"></a> [etcd\_backup\_container\_url](#output\_etcd\_backup\_container\_url) | URL of the etcd-snapshots container; snapshots sit under <name>/<server>/<file>. Null when etcd\_backup is disabled. |
| <a name="output_etcd_backup_storage_account_id"></a> [etcd\_backup\_storage\_account\_id](#output\_etcd\_backup\_storage\_account\_id) | Resource ID of the etcd snapshot storage account, null when etcd\_backup is disabled. The scope for a private endpoint or extra grants. |
| <a name="output_external_dns_client_id"></a> [external\_dns\_client\_id](#output\_external\_dns\_client\_id) | Client ID of the external-dns workload identity, null when disabled. |
| <a name="output_external_dns_identity_id"></a> [external\_dns\_identity\_id](#output\_external\_dns\_identity\_id) | Resource ID of the external-dns workload identity, null when disabled. |
| <a name="output_external_dns_principal_id"></a> [external\_dns\_principal\_id](#output\_external\_dns\_principal\_id) | Principal ID of the external-dns workload identity, for role assignments you create yourself. |
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | ID of the Key Vault holding the tokens, the CA set and the generated SSH key. |
| <a name="output_key_vault_name"></a> [key\_vault\_name](#output\_key\_vault\_name) | Name of that Key Vault. |
| <a name="output_kube_exec"></a> [kube\_exec](#output\_kube\_exec) | kubelogin exec block for the helm provider and cni-bootstrap, null unless entra\_oidc is on. Without it, use admin\_client\_certificate and admin\_client\_key. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig for cluster\_endpoint with the client certificate, the break-glass path. With entra\_oidc on, people and pipelines use kubeconfig\_entra. |
| <a name="output_kubeconfig_entra"></a> [kubeconfig\_entra](#output\_kubeconfig\_entra) | Kubeconfig for cluster\_endpoint with the kubelogin exec block, null unless entra\_oidc is on. It holds no secret: kubelogin fetches the token. |
| <a name="output_location"></a> [location](#output\_location) | Azure region of the stack. |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | Public IP addresses of the NAT Gateway, for allow lists. Empty with existing\_vnet. |
| <a name="output_node_resource_group_name"></a> [node\_resource\_group\_name](#output\_node\_resource\_group\_name) | Resource group holding the nodes and what the cloud provider and CSI driver create. |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | ID of the network security group on every node, where cloud-provider-azure adds Service rules. |
| <a name="output_node_subnet_id"></a> [node\_subnet\_id](#output\_node\_subnet\_id) | ID of the subnet every node and private endpoint uses. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer URL of the cluster, null when workload identity is off. Use it for federated identity credentials you create yourself. |
| <a name="output_region"></a> [region](#output\_region) | Same value as location, for consumers that expect an output named region. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group holding the network, Key Vault, identities and load balancers. |
| <a name="output_selinux_container_dirs_resolved"></a> [selinux\_container\_dirs\_resolved](#output\_selinux\_container\_dirs\_resolved) | Host directories the bootstrap labels container\_file\_t on a host with SELinux on, from the CNI profile; introspection for tests. |
| <a name="output_server_config_resolved"></a> [server\_config\_resolved](#output\_server\_config\_resolved) | RKE2 server config.yaml as a map, without the join drop-ins. |
| <a name="output_server_identity_client_id"></a> [server\_identity\_client\_id](#output\_server\_identity\_client\_id) | Client ID of the server identity, which cloud-provider-azure and cluster-autoscaler use. |
| <a name="output_server_identity_id"></a> [server\_identity\_id](#output\_server\_identity\_id) | Resource ID of the server identity. |
| <a name="output_server_identity_principal_id"></a> [server\_identity\_principal\_id](#output\_server\_identity\_principal\_id) | Principal ID of the server identity, for extra role assignments. |
| <a name="output_server_manifests_resolved"></a> [server\_manifests\_resolved](#output\_server\_manifests\_resolved) | Manifests every server writes to the RKE2 manifests directory, file name to YAML. |
| <a name="output_server_vm_ids"></a> [server\_vm\_ids](#output\_server\_vm\_ids) | Resource IDs of the server VMs, in index order. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Azure subscription the stack runs in. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra tenant of the subscription. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | ID of the VNet, created or taken from existing\_vnet. |
| <a name="output_workload_identity_enabled_resolved"></a> [workload\_identity\_enabled\_resolved](#output\_workload\_identity\_enabled\_resolved) | Which workload identities are created, after enabled and overrides. |
| <a name="output_workload_identity_service_accounts_resolved"></a> [workload\_identity\_service\_accounts\_resolved](#output\_workload\_identity\_service\_accounts\_resolved) | Namespace and service account each created identity federates with. |
<!-- END_TF_DOCS -->
