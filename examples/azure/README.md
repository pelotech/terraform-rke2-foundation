# examples/azure

A complete, applyable root for the Azure module against a live subscription: the stack with the kube-ovn
profile, cni-bootstrap over the admin client certificate, and the Azure disk CSI driver so the smoke test
can bind a PVC. It is the way to exercise the paths the mocked tests cannot: the Key Vault fetch through
IMDS, cloud-provider-azure, the load balancer during joins, the OIDC issuer publish and a disk mount.

## Run it

1. Authenticate the azurerm provider against the right cloud and export the subscription:

   ```bash
   az cloud set --name AzureUSGovernment && az login
   export ARM_SUBSCRIPTION_ID=<subscription id>
   ```

2. Copy `terraform.tfvars.example` to `terraform.tfvars`. Set `authorized_ip_ranges` to the egress address
   of this host and `key_vault_admin_object_ids` to the principal applying the example:

   ```bash
   az ad signed-in-user show --query id -o tsv
   ```

3. Apply. Expect about fifteen minutes: the VMs come up within a few, RKE2 and the CNI take the rest, and
   cni-bootstrap's node poll bridges the gap.

   ```bash
   terraform init && terraform apply
   ```

   To test a cni-bootstrap change, a gitignored `cni_override.tf` with a `module "cni"` block can point
   `source` at a local clone. Remove it before you regenerate the docs.

4. Run the smoke test with the kubeconfig output:

   ```bash
   (umask 077 && terraform output -raw kubeconfig > kubeconfig)
   KUBECONFIG=$PWD/kubeconfig ./smoke-test.sh
   ```

## What a green run proves

| Step | Azure path it exercises |
| --- | --- |
| Nodes register | cloud-init fetched the tokens and the CA set from Key Vault through IMDS, the internal load balancer answered on 9345 for the joins |
| Nodes Ready | cni-bootstrap reached the API through the public load balancer with the client certificate and installed the CNI |
| A LoadBalancer Service gets an address | cloud-provider-azure runs with the server identity and can write the node resource group and the security group |
| The PVC binds and mounts | the disk CSI driver reads the same cloud config and creates a disk in the node resource group |
| `oidc_issuer_url` serves `.well-known/openid-configuration` | the servers published the discovery document and JWKS to the static website |

Check the last one with `curl "$(terraform output -raw oidc_issuer_url).well-known/openid-configuration"`.

## Tear down

Before you destroy, delete the namespaces that hold PVCs, or set `install_disk_csi = false`.
`terraform destroy` then removes every resource. Azure keeps the Key Vault soft-deleted for 90 days, with
purge protection, and a later apply with the same `name` recovers it. See the docs section "Destroy and create
again".

## Cost

Three servers, two agents and one kube-ovn node at the three `*_vm_size` inputs, one NAT Gateway, two Standard
load balancers, one Key Vault and two storage accounts, for the OIDC issuer and the etcd snapshots.
Subscriptions with a 10 vCPU cap per family, such as a
Visual Studio one, need a different family per role. Destroy when done.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cni"></a> [cni](#module\_cni) | github.com/pelotech/terraform-helm-cni-bootstrap | v1.1.0 |
| <a name="module_stack"></a> [stack](#module\_stack) | ../../modules/azure | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.disk_csi](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_authorized_ip_ranges"></a> [authorized\_ip\_ranges](#input\_authorized\_ip\_ranges) | CIDRs allowed to reach the public API server: the egress address of the host that applies this example, at least. | `list(string)` | n/a | yes |
| <a name="input_key_vault_admin_object_ids"></a> [key\_vault\_admin\_object\_ids](#input\_key\_vault\_admin\_object\_ids) | Entra object ids that may write the Key Vault secrets. Include the principal that applies this example. | `list(string)` | n/a | yes |
| <a name="input_agent_vm_size"></a> [agent\_vm\_size](#input\_agent\_vm\_size) | VM size of the general agent pool. | `string` | `"Standard_D4s_v5"` | no |
| <a name="input_azure_cloud"></a> [azure\_cloud](#input\_azure\_cloud) | Azure cloud for both the azurerm provider and the stack: public or usgovernment. | `string` | `"usgovernment"` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | CNI profile of the stack: cilium, kube-ovn or canal. | `string` | `"kube-ovn"` | no |
| <a name="input_cni_vm_size"></a> [cni\_vm\_size](#input\_cni\_vm\_size) | VM size of the kube-ovn node. ovn-central and kube-ovn-controller need about 2 vCPUs and 3 GB on it. | `string` | `"Standard_D4s_v5"` | no |
| <a name="input_disk_csi_chart_version"></a> [disk\_csi\_chart\_version](#input\_disk\_csi\_chart\_version) | azuredisk-csi-driver chart version. | `string` | `"v1.30.10"` | no |
| <a name="input_install_disk_csi"></a> [install\_disk\_csi](#input\_install\_disk\_csi) | Installs the Azure disk CSI driver so the smoke test can bind a PVC. | `bool` | `true` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | `"usgovvirginia"` | no |
| <a name="input_name"></a> [name](#input\_name) | Cluster name and base of every resource name. | `string` | `"rke2-dev"` | no |
| <a name="input_server_vm_size"></a> [server\_vm\_size](#input\_server\_vm\_size) | VM size of the three server nodes. | `string` | `"Standard_D4s_v5"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. Owner seeds the storage account names. | `map(string)` | <pre>{<br/>  "Environment": "dev",<br/>  "Owner": "pelotech"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_public_fqdn"></a> [api\_public\_fqdn](#output\_api\_public\_fqdn) | Public FQDN of the API server. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | API server URL. |
| <a name="output_key_vault_name"></a> [key\_vault\_name](#output\_key\_vault\_name) | Key Vault holding the join tokens and the CA set. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig. Write it to a file and point KUBECONFIG at it for smoke-test.sh. |
| <a name="output_node_resource_group_name"></a> [node\_resource\_group\_name](#output\_node\_resource\_group\_name) | Resource group of the nodes, where the cloud provider creates load balancers and disks. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer the servers publish for workload identity. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group of the network, vault and identities. |
| <a name="output_server_identity_client_id"></a> [server\_identity\_client\_id](#output\_server\_identity\_client\_id) | Client id of the server identity, which cloud-provider-azure and the CSI controller use. |
<!-- END_TF_DOCS -->
