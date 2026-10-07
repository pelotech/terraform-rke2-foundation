# modules/bootstrap

The cloud-neutral part of an RKE2 foundation. Given the registration address and the cluster settings
it generates:

- the custom CA set RKE2 adopts from `/var/lib/rancher/rke2/server/tls` on first start, and the
  service account signing key
- the server and agent join tokens
- an admin client certificate signed by the client CA, and a kubeconfig
- `config.yaml` for servers and for each agent pool
- cloud-init for server node 0, the other server nodes and each agent pool

Secrets never enter cloud-init. The cloud module stores the `server_secret_contents` in its secret store and
provides `fetch_secrets_scripts`, shell that writes each secret to `<SECRET_DIR>/<path>` from
`server_secret_paths` or `agent_secret_paths`. `bootstrap.sh` fetches the secrets. On a server node with
`etcd_disk_device`, it formats and mounts the etcd disk. It installs the files and installs RKE2 with
`INSTALL_RKE2_VERSION` and `INSTALL_RKE2_TYPE`. It probes the registration address to decide between
bootstrap and join. It starts the service. On a server node, it runs `post_bootstrap_script` once the API
answers. Then it enables the renewal timer and, on a server node, the snapshot timer.

`server:` and `token:` are never in `config.yaml`; `bootstrap.sh` writes them as drop-ins under
`/etc/rancher/rke2/config.yaml.d/`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [random_password.agent_token](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.token](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [tls_cert_request.admin](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_locally_signed_cert.admin](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_private_key.admin](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.service_account](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_dns"></a> [cluster\_dns](#input\_cluster\_dns) | Cluster DNS service IP inside service\_cidr, the RKE2 cluster-dns. | `string` | n/a | yes |
| <a name="input_fetch_secrets_scripts"></a> [fetch\_secrets\_scripts](#input\_fetch\_secrets\_scripts) | Shell each role sources as root. It must define fetch NAME PATH, which writes that secret to <SECRET\_DIR>/<PATH>; bootstrap.sh calls it for every entry of server\_secret\_paths or agent\_secret\_paths. | <pre>object({<br/>    server = string<br/>    agent  = string<br/>  })</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Cluster name. It prefixes the CA common names and names the kubeconfig context. | `string` | n/a | yes |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Pod CIDR, the RKE2 cluster-cidr. | `string` | n/a | yes |
| <a name="input_registration_address"></a> [registration\_address](#input\_registration\_address) | Host or IP every node joins through on port 9345, the fixed registration address. Always part of tls-san. | `string` | n/a | yes |
| <a name="input_rke2_version"></a> [rke2\_version](#input\_rke2\_version) | RKE2 release to install, v1.36.0+rke2r1 or newer, for example v1.36.5+rke2r1. Passed to the install script as INSTALL\_RKE2\_VERSION. | `string` | n/a | yes |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | Kubernetes service CIDR, the RKE2 service-cidr. | `string` | n/a | yes |
| <a name="input_agent_pools"></a> [agent\_pools](#input\_agent\_pools) | Agent pools to render cloud-init for, keyed by pool name. Taints are key=value:Effect strings. | <pre>map(object({<br/>    labels       = optional(map(string), {})<br/>    taints       = optional(list(string), [])<br/>    kubelet_args = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_api_server_url"></a> [api\_server\_url](#input\_api\_server\_url) | API server URL in the admin kubeconfig. null uses https://<registration\_address>:6443. | `string` | `null` | no |
| <a name="input_bootstrap_wait_seconds"></a> [bootstrap\_wait\_seconds](#input\_bootstrap\_wait\_seconds) | How long server zero waits for the registration address before it bootstraps a new cluster. Other servers and agents wait without limit. | `number` | `90` | no |
| <a name="input_certificate_renewal"></a> [certificate\_renewal](#input\_certificate\_renewal) | Renews node certificates on the node itself. A daily timer runs rke2 certificate check; when a certificate is inside RKE2's renewal window, an agent restarts rke2-agent, and a server rotates its keys with rke2 certificate rotate and restarts, one server at a time through a Lease in kube-system. | `bool` | `true` | no |
| <a name="input_cis_profile"></a> [cis\_profile](#input\_cis\_profile) | Sets profile: cis and performs the host prerequisites before RKE2 starts: the etcd user and the CIS sysctl file. | `bool` | `false` | no |
| <a name="input_cloud_provider_name"></a> [cloud\_provider\_name](#input\_cloud\_provider\_name) | RKE2 cloud-provider-name, for example external. Setting it also disables the RKE2 default cloud controller. null keeps that controller. | `string` | `null` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | RKE2 cni value: none for a CNI installed afterwards, or a bundled one: canal, cilium or calico. | `string` | `"none"` | no |
| <a name="input_disable_components"></a> [disable\_components](#input\_disable\_components) | Packaged components RKE2 must not deploy: rke2-coredns, rke2-metrics-server, rke2-snapshot-controller, rke2-snapshot-controller-crd, rke2-snapshot-validation-webhook, and from v1.37 rke2-security-responder and rke2-gateway-api-crd. The ingress is ingress\_controller. | `list(string)` | `[]` | no |
| <a name="input_disable_firewalld"></a> [disable\_firewalld](#input\_disable\_firewalld) | Stops and disables firewalld when the image ships it, as RKE2 documents it as incompatible with its networking. Set false on an image whose firewalld rules allow the RKE2 ports. | `bool` | `true` | no |
| <a name="input_disable_kube_proxy"></a> [disable\_kube\_proxy](#input\_disable\_kube\_proxy) | Sets disable-kube-proxy, for a CNI that replaces kube-proxy. | `bool` | `false` | no |
| <a name="input_etcd_disk_device"></a> [etcd\_disk\_device](#input\_etcd\_disk\_device) | Block device for the etcd directory of a server, for example /dev/disk/azure/scsi1/lun0. bootstrap.sh waits for it, formats it with XFS when it carries no filesystem, and mounts it on the server db directory before RKE2 starts. null keeps etcd on the root disk. | `string` | `null` | no |
| <a name="input_extra_agent_config"></a> [extra\_agent\_config](#input\_extra\_agent\_config) | RKE2 agent config keys merged last into every agent's config.yaml. They override the keys the module sets. | `any` | `{}` | no |
| <a name="input_extra_server_config"></a> [extra\_server\_config](#input\_extra\_server\_config) | RKE2 server config keys merged last into config.yaml. They override the keys the module sets. | `any` | `{}` | no |
| <a name="input_ingress_controller"></a> [ingress\_controller](#input\_ingress\_controller) | Packaged ingress controller: none, traefik or ingress-nginx. The GitOps layer provides the ingress, as on AKS, so the default is none. | `string` | `"none"` | no |
| <a name="input_install_script_url"></a> [install\_script\_url](#input\_install\_script\_url) | URL of the RKE2 install script. Point it at a mirror in restricted networks. | `string` | `"https://get.rke2.io"` | no |
| <a name="input_kube_apiserver_args"></a> [kube\_apiserver\_args](#input\_kube\_apiserver\_args) | kube-apiserver-arg entries, as flag=value strings. | `list(string)` | `[]` | no |
| <a name="input_kube_controller_manager_args"></a> [kube\_controller\_manager\_args](#input\_kube\_controller\_manager\_args) | kube-controller-manager-arg entries, as flag=value strings. | `list(string)` | `[]` | no |
| <a name="input_kubelet_args"></a> [kubelet\_args](#input\_kubelet\_args) | kubelet-arg entries for every node, as flag=value strings. | `list(string)` | `[]` | no |
| <a name="input_pki"></a> [pki](#input\_pki) | Validity of the CA set and of the admin client certificate, which Terraform renews admin\_early\_renewal\_hours before it expires. | <pre>object({<br/>    ca_validity_hours         = optional(number, 87600)<br/>    admin_validity_hours      = optional(number, 8760)<br/>    admin_early_renewal_hours = optional(number, 720)<br/>  })</pre> | `{}` | no |
| <a name="input_post_bootstrap_script"></a> [post\_bootstrap\_script](#input\_post\_bootstrap\_script) | Shell every server runs once the API answers /readyz, with KUBECONFIG set and kubectl on PATH. Empty runs nothing. | `string` | `""` | no |
| <a name="input_put_snapshot_script"></a> [put\_snapshot\_script](#input\_put\_snapshot\_script) | Shell every server sources as root. It must define put\_snapshot PATH FILE, which stores FILE at PATH outside the node. With it, an hourly timer uploads each new etcd snapshot once. Empty installs no timer. | `string` | `""` | no |
| <a name="input_secrets_encryption"></a> [secrets\_encryption](#input\_secrets\_encryption) | Sets secrets-encryption, RKE2's encryption of Secrets at rest in etcd. | `bool` | `true` | no |
| <a name="input_server_labels"></a> [server\_labels](#input\_server\_labels) | Node labels for every server. | `map(string)` | `{}` | no |
| <a name="input_server_manifests"></a> [server\_manifests](#input\_server\_manifests) | Manifests every server writes to /var/lib/rancher/rke2/server/manifests before RKE2 starts, file name to YAML. | `map(string)` | `{}` | no |
| <a name="input_server_taints"></a> [server\_taints](#input\_server\_taints) | Node taints for every server as key=value:Effect strings. Empty makes servers schedulable. | `list(string)` | <pre>[<br/>  "CriticalAddonsOnly=true:NoSchedule"<br/>]</pre> | no |
| <a name="input_tls_sans"></a> [tls\_sans](#input\_tls\_sans) | Extra Subject Alternative Names for the API server certificate, for example a public FQDN. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_client_certificate"></a> [admin\_client\_certificate](#output\_admin\_client\_certificate) | PEM admin client certificate, system:admin in system:masters, signed by the client CA. |
| <a name="output_admin_client_key"></a> [admin\_client\_key](#output\_admin\_client\_key) | PEM private key of the admin client certificate. |
| <a name="output_agent_config"></a> [agent\_config](#output\_agent\_config) | RKE2 agent config.yaml as a map per pool, without the join drop-ins. |
| <a name="output_agent_secret_paths"></a> [agent\_secret\_paths](#output\_agent\_secret\_paths) | Secret name to the path under SECRET\_DIR an agent's fetch script must write it to. |
| <a name="output_agent_user_data"></a> [agent\_user\_data](#output\_agent\_user\_data) | cloud-init per agent pool. |
| <a name="output_client_ca_certificate"></a> [client\_ca\_certificate](#output\_client\_ca\_certificate) | PEM of the CA that signs client certificates, the admin credential among them. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig: api\_server\_url, the server CA and the admin client certificate. |
| <a name="output_server_ca_certificate"></a> [server\_ca\_certificate](#output\_server\_ca\_certificate) | PEM of the CA that signs the API server certificate. Clients verify the API with it. |
| <a name="output_server_config"></a> [server\_config](#output\_server\_config) | RKE2 server config.yaml as a map, without the join drop-ins. |
| <a name="output_server_secret_contents"></a> [server\_secret\_contents](#output\_server\_secret\_contents) | Secret name to content, every secret in server\_secret\_paths, for the cloud module to store. |
| <a name="output_server_secret_paths"></a> [server\_secret\_paths](#output\_server\_secret\_paths) | Secret name to the path under SECRET\_DIR a server's fetch script must write it to. |
| <a name="output_server_user_data"></a> [server\_user\_data](#output\_server\_user\_data) | cloud-init for servers: init\_candidate for server zero, member for the others. |
| <a name="output_service_account_public_key"></a> [service\_account\_public\_key](#output\_service\_account\_public\_key) | PEM public key matching the service account signing key, for a JWKS built outside the cluster. |
<!-- END_TF_DOCS -->
