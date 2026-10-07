# Bootstrap

This page shows how a node becomes part of the cluster. Nothing on this page needs a CLI on the host that
runs Terraform.

## Sequence

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform
    participant KV as Key Vault
    participant S0 as Server node 0
    participant LB as Registration address
    participant SN as Server nodes 1 and 2
    participant AG as Agent node
    participant ST as OIDC storage
    TF->>KV: Write the tokens and the CA set
    TF->>S0: Create the VM with its cloud-init
    S0->>KV: Read the secrets with the server identity through IMDS
    S0->>S0: Write the CA set, install RKE2
    S0->>LB: GET /ping on 9345
    LB-->>S0: No answer within bootstrap_wait_seconds
    S0->>S0: Start a new cluster
    SN->>LB: GET /ping on 9345, until 200
    SN->>S0: Join through the registration address
    AG->>KV: Read the agent token with the agent identity
    AG->>LB: Join on 9345
    S0->>S0: Wait for /readyz
    S0->>ST: Publish the discovery document and the JWKS, every server node does
```

## Start or join

Only server node 0 may start a new cluster. It waits `servers.bootstrap_wait_seconds` for the registration
address. A replaced server node 0 therefore joins the running cluster.

Two servers that join etcd at the same moment make one of them fail its first start with a join deadline
error. systemd restarts the service five seconds later and the second attempt joins. The bootstrap waits for
`/readyz` through it and still ends with `done`.

On RHEL 10 the bootstrap installs `kernel-modules-extra` for the running kernel before RKE2. The Azure
Marketplace image ships without the iptables modules that kube-proxy and kube-ovn need, and the RKE2 RPM pulls
the build of the newest kernel, which runs only after a reboot.

```mermaid
flowchart TD
  A["Node boots"] --> B["Fetch secrets"]
  B --> C["Install RKE2"]
  C --> D{"Server node 0?"}
  D -- no --> E["Wait until /ping answers 200"]
  E --> F["Write server: https://ADDRESS:9345"]
  D -- yes --> G{"/ping answers 200<br/>within the wait?"}
  G -- yes --> F
  G -- no --> H["Start a new cluster"]
  F --> I["Start rke2-server or rke2-agent"]
  H --> I
  I --> J{"Server node?"}
  J -- yes --> K["Wait for /readyz, run post-bootstrap"]
  J -- no --> L["Done"]
  K --> L
```

## Files on a node

| Path                                          | Content                                   | Written by           |
| --------------------------------------------- | ----------------------------------------- | -------------------- |
| `/etc/rancher/rke2/config.yaml`               | RKE2 settings, no secrets                 | cloud-init           |
| `/etc/rancher/rke2/config.yaml.d/00-join.yaml`| `server:` the registration address        | bootstrap.sh         |
| `/etc/rancher/rke2/config.yaml.d/10-token.yaml`| the join token, mode 0600                | bootstrap.sh         |
| `/var/lib/rancher/rke2/server/tls/`           | the CA set, mode 0600, servers only       | bootstrap.sh         |
| `/var/lib/rancher/rke2/server/db/`            | the etcd data disk, mounted, servers only | bootstrap.sh         |
| `/var/lib/rancher/rke2/server/manifests/`     | cloud-provider-azure, servers only        | cloud-init           |
| `/etc/rke2-foundation/env`                    | role, addresses, the secret list          | cloud-init           |
| `/usr/local/lib/rke2-foundation/`             | bootstrap.sh, fetch-secrets.sh, post-bootstrap.sh, renew-certificates.sh, upload-snapshots.sh, put-snapshot.sh | cloud-init |
| `/var/log/cloud-init-output.log`              | the bootstrap log, lines start with `rke2-foundation:` | cloud-init |

Cloud-init carries names, addresses and scripts. It never carries a secret.

## Where the secrets live

| Secret                        | Terraform state | Key Vault | Node                                   |
| ----------------------------- | --------------- | --------- | -------------------------------------- |
| CA private keys               | yes             | yes       | servers, `server/tls/`                 |
| Service account signing key   | yes             | yes       | servers, `server/tls/service.key`      |
| Server join token             | yes             | yes       | servers, `10-token.yaml`               |
| Agent join token              | yes             | yes       | every node, `10-token.yaml`            |
| Admin client key              | yes             | no        | no                                     |
| Generated SSH private key     | yes             | yes       | no                                     |

Protect the state as you protect the vault.
