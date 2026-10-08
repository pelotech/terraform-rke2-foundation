# examples/local

Runs the cloud-neutral half of the bootstrap on your computer with Multipass. [Local test](../../docs/LOCAL-TEST.md)
says what it proves. The root here renders `modules/bootstrap` for a cluster of three server nodes, one agent
node and, for kube-ovn, one more node; `cni/` installs the CNI through cni-bootstrap; `run.sh` drives the VMs.

```bash
./run.sh up kube-ovn   # or: ./run.sh up cilium
./run.sh cni
./run.sh status
./run.sh down
```

`fetch-stub.sh` stands in for the Key Vault: it copies the secrets that `run.sh` seeded on the VM.
`put-snapshot-stub.sh` stands in for the blob container: it copies each snapshot under
`/var/tmp/rke2-snapshot-uploads`. Everything under `stage/` is generated and ignored by git, the kubeconfig
included.

To test a cni-bootstrap change, add a gitignored `cni/cni_override.tf` that points the `cni` module `source`
at a local clone.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bootstrap"></a> [bootstrap](#module\_bootstrap) | ../../modules/bootstrap | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_registration_address"></a> [registration\_address](#input\_registration\_address) | Address of the haproxy VM; run.sh fills it in. | `string` | n/a | yes |
| <a name="input_cni"></a> [cni](#input\_cni) | Profile to render: cilium or kube-ovn. | `string` | `"kube-ovn"` | no |
| <a name="input_rke2_version"></a> [rke2\_version](#input\_rke2\_version) | RKE2 release to install on the VMs. | `string` | `"v1.37.1+rke2r1"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_client_certificate"></a> [admin\_client\_certificate](#output\_admin\_client\_certificate) | Base64 PEM of the admin client certificate. |
| <a name="output_admin_client_key"></a> [admin\_client\_key](#output\_admin\_client\_key) | Base64 PEM of the admin client key. |
| <a name="output_agent_secret_paths"></a> [agent\_secret\_paths](#output\_agent\_secret\_paths) | Secret name to path for agents. |
| <a name="output_agent_user_data"></a> [agent\_user\_data](#output\_agent\_user\_data) | cloud-init per agent pool. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64 PEM of the server CA. |
| <a name="output_cni_node_selector"></a> [cni\_node\_selector](#output\_cni\_node\_selector) | Selector of those nodes, as the Azure module computes it. |
| <a name="output_cni_node_size"></a> [cni\_node\_size](#output\_cni\_node\_size) | Nodes cni-bootstrap waits for, as the Azure module computes it. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig against the registration address. |
| <a name="output_server_secret_contents"></a> [server\_secret\_contents](#output\_server\_secret\_contents) | Secret name to content, seeded onto the VMs by run.sh. |
| <a name="output_server_secret_paths"></a> [server\_secret\_paths](#output\_server\_secret\_paths) | Secret name to path for servers. |
| <a name="output_server_user_data"></a> [server\_user\_data](#output\_server\_user\_data) | cloud-init for the init candidate and the other servers. |
<!-- END_TF_DOCS -->
