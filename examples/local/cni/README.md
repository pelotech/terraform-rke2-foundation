# Local CNI root

Installs the CNI through cni-bootstrap on the Multipass cluster that `../run.sh up` created. `../run.sh cni`
applies it; see [the local example](../README.md).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cni"></a> [cni](#module\_cni) | github.com/pelotech/terraform-helm-cni-bootstrap | 65df8664c1bf78d4043d7df711cb7a4c03f04181 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ca"></a> [ca](#input\_ca) | Base64 PEM of the server CA. | `string` | n/a | yes |
| <a name="input_cert"></a> [cert](#input\_cert) | Base64 PEM of the admin client certificate. | `string` | n/a | yes |
| <a name="input_cni"></a> [cni](#input\_cni) | Profile: cilium or kube-ovn. | `string` | n/a | yes |
| <a name="input_cni_node_selector"></a> [cni\_node\_selector](#input\_cni\_node\_selector) | Selector of those nodes. | `string` | n/a | yes |
| <a name="input_cni_node_size"></a> [cni\_node\_size](#input\_cni\_node\_size) | Nodes the poll waits for. | `number` | n/a | yes |
| <a name="input_endpoint"></a> [endpoint](#input\_endpoint) | API server URL. | `string` | n/a | yes |
| <a name="input_key"></a> [key](#input\_key) | Base64 PEM of the admin client key. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_resolved_set"></a> [resolved\_set](#output\_resolved\_set) | Helm --set values cni-bootstrap installed. |
<!-- END_TF_DOCS -->
