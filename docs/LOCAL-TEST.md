# Local test

The bootstrap does not depend on Azure until a node reads its secrets. [`examples/local`](../examples/local/README.md)
runs the cloud-neutral half on your computer with Multipass. It creates three server nodes, one agent node, one
extra node for kube-ovn, and a haproxy VM as the registration address.

## What it proves

- RKE2 adopts the CA set that Terraform generated.
- Server node 0 starts the cluster, the other nodes join through the registration address.
- The admin kubeconfig that Terraform minted works.
- cni-bootstrap installs Cilium or kube-ovn with the client certificate.
- A replaced server node 0 joins instead of starting a second cluster. `run.sh` has no step for it: delete
  the VM and launch it again by hand.

## What it does not prove

The Key Vault fetch through IMDS, cloud-provider-azure, the Azure load balancer and the OIDC publish need
the [Azure example](../examples/azure/README.md). Entra login and FIPS on RHEL have no example yet.

## Procedure

1. Install Multipass, Terraform and kubectl. Keep 24 GB of memory free.
2. Run `./run.sh up kube-ovn` or `./run.sh up cilium` in `examples/local`. It launches the VMs, configures
   haproxy, renders the cloud-init from `modules/bootstrap`, stages it and waits for every node to register.
3. Run `./run.sh cni`. It installs the CNI through cni-bootstrap and waits for every node to be Ready.
4. Run `./run.sh status` at any time. The kubeconfig is in `stage/kubeconfig`.
5. Run `./run.sh down` to delete the VMs.

The haproxy VM refuses connections while no server node is healthy, as the Azure load balancer does. The
bootstrap decides on a 200 from `/ping`, so a refused connection counts as no answer.

After a purge, Multipass can give two new VMs the same MAC address, so they share one DHCP address and
`multipass list` shows the same IPv4 twice. Run `./run.sh down` and `./run.sh up` again; the new VMs get
new addresses.
