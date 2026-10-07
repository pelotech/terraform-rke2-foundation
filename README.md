# terraform-rke2-foundation

Terraform modules for an RKE2 cluster with its cloud plumbing, one submodule per cloud. It is the third
foundation, next to terraform-aws-foundation for EKS and terraform-azure-foundation for AKS. Every
foundation emits the same outputs, so terraform-helm-cni-bootstrap and the GitOps layer do not care which
distribution runs.

| Module                                      | Providers      | What it builds                                                                 |
| ------------------------------------------- | -------------- | ------------------------------------------------------------------------------ |
| [`modules/azure`](modules/azure/README.md)         | azurerm, tls   | Resource groups, VNet, NAT Gateway, API load balancers, server VMs, agent scale sets, Key Vault, identities, OIDC issuer, blob CSI storage, etcd snapshot storage |
| [`modules/bootstrap`](modules/bootstrap/README.md) | tls, random    | The RKE2 CA set, join tokens, admin credential, `config.yaml` and cloud-init. Cloud-neutral; the cloud modules call it |

The repo name breaks pelotech's `terraform-<provider>-<name>` pattern on purpose: that pattern cannot
express a repo that holds several providers. Consumers reference a submodule by git ref:

```hcl
module "stack" {
  source = "github.com/pelotech/terraform-rke2-foundation//modules/azure?ref=<release tag>"
}
```

## What RKE2 does the same on every cloud

- Server nodes hold the control plane and etcd behind a fixed registration address on ports 6443 and 9345.
  Server node 0 starts a new cluster only when nothing answers there. Every other node joins.
- The CA set, the join tokens and the admin client certificate come from Terraform, so the API
  endpoint, its CA and a credential are known at plan time. No apply-time polling, no CLI on the host.
- Secrets never travel in cloud-init. Nodes fetch them from the cloud's secret store with their identity.
- `cni: none` plus cni-bootstrap for Cilium and kube-ovn, or the bundled, FIPS-rebuilt Canal.
- Every node runs RKE2's local API load balancer on `127.0.0.1:6443`; Cilium uses it as `k8sServiceHost`.

## The contract

| Output                   | cni-bootstrap input       | Value on RKE2                                                  |
| ------------------------ | ------------------------- | -------------------------------------------------------------- |
| `cloud`                  | `cloud`                   | `azure`                                                        |
| `distribution`           | `distribution`            | `rke2`                                                         |
| `cluster_endpoint`       | `cluster_endpoint`        | `https://<api host>:6443`                                      |
| `cluster_ca_certificate` | `cluster_ca_certificate`  | base64 PEM of the RKE2 server CA                               |
| `admin_client_certificate`, `admin_client_key` | `client_certificate`, `client_key` | base64 PEM, system:masters |
| `kube_exec`              | `kube_exec`               | kubelogin block when `entra_oidc` is on, else null             |
| `cluster_api_host`       | `k8s_service_host`        | `127.0.0.1`                                                    |
| `cluster_api_port`       | `k8s_service_port`        | `6443`                                                         |
| `cluster_service_cidr`   | `service_cidr`            | `service_cidr`                                                 |
| `cluster_pod_cidr`       | `pod_cidr`                | `pod_cidr`                                                     |
| `cni_node_size`          | `wait_for_nodes_count`    | server count, or the CNI pool size for kube-ovn                |
| `cni_node_selector`      | `wait_for_nodes_selector` | `node-role.kubernetes.io/control-plane=true`, or the kube-ovn master label |

`cni_node_size` counts the servers on purpose: cni-bootstrap's node poll then waits for the API before
Helm connects, because Terraform finishes creating the VMs minutes before RKE2 answers.

## Try it on Azure

[`examples/azure`](examples/azure/README.md) is a complete root for a live subscription, with a smoke test
that exercises the paths the mocked tests cannot.

## Development

```bash
for m in modules/bootstrap modules/azure; do (cd "$m" && terraform init -backend=false && terraform test); done
```

azurerm is mocked; tls and random run for real. `prek run --all-files` runs the hooks CI runs. The dev
shell in `flake.nix` holds every tool.

## Docs

- [Architecture](docs/ARCHITECTURE.md): what the module builds and how the parts connect.
- [Bootstrap](docs/BOOTSTRAP.md): how a node joins, and where every secret lives.
- [Operations](docs/OPERATIONS.md): replace a server, roll a pool, upgrade, rotate.
- [Security](docs/SECURITY.md): identities, grants, exposure, hardening.
- [Local test](docs/LOCAL-TEST.md): the Multipass run that proves the bootstrap without Azure.

## Design

[`docs/superpowers/specs/2026-10-05-rke2-foundation-design.md`](docs/superpowers/specs/2026-10-05-rke2-foundation-design.md)
