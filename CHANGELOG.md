# Changelog

## [0.2.1](https://github.com/pelotech/terraform-rke2-foundation/compare/v0.2.0...v0.2.1) (2026-10-08)


### Bug Fixes

* **azure:** find the etcd disk through the by-lun link so NVMe servers boot ([#27](https://github.com/pelotech/terraform-rke2-foundation/issues/27)) ([14121a5](https://github.com/pelotech/terraform-rke2-foundation/commit/14121a5de3f3865f8ff241aa6248e3a025b5fb10))

## [0.2.0](https://github.com/pelotech/terraform-rke2-foundation/compare/v0.1.2...v0.2.0) (2026-10-08)


### Features

* **azure:** tag pools with their labels and taints for a scale from zero ([#23](https://github.com/pelotech/terraform-rke2-foundation/issues/23)) ([f5b106d](https://github.com/pelotech/terraform-rke2-foundation/commit/f5b106d5ad509345040c36612bc6388d10f74111))


### Bug Fixes

* **azure:** keep the agent pools in the load balancer across applies ([#25](https://github.com/pelotech/terraform-rke2-foundation/issues/25)) ([1d5d0a1](https://github.com/pelotech/terraform-rke2-foundation/commit/1d5d0a157df988879d8043a714abe06832b262c9))
* **bootstrap:** grow /var into the free space of its volume group ([#22](https://github.com/pelotech/terraform-rke2-foundation/issues/22)) ([c146b0b](https://github.com/pelotech/terraform-rke2-foundation/commit/c146b0bb37a6ecd7942038a2cdca52a5d237ecb0))

## [0.1.2](https://github.com/pelotech/terraform-rke2-foundation/compare/v0.1.1...v0.1.2) (2026-10-08)


### Bug Fixes

* **azure:** expose the id of the OIDC storage account ([#20](https://github.com/pelotech/terraform-rke2-foundation/issues/20)) ([7007a64](https://github.com/pelotech/terraform-rke2-foundation/commit/7007a64ecc6dfdef2827f41116fd2fbec13802d0))

## [0.1.1](https://github.com/pelotech/terraform-rke2-foundation/compare/v0.1.0...v0.1.1) (2026-10-08)


### Bug Fixes

* **azure:** treat a null Entra username prefix as none ([#18](https://github.com/pelotech/terraform-rke2-foundation/issues/18)) ([db3af42](https://github.com/pelotech/terraform-rke2-foundation/commit/db3af42bb8c30aee12c99e91c8c31e8076cba60a))

## 0.1.0 (2026-10-08)


### Features

* add the RKE2 foundation with the bootstrap and Azure modules ([c4ab976](https://github.com/pelotech/terraform-rke2-foundation/commit/c4ab976a64c9bc7b6498010f3ab7e1f20d19674d))
* **azure:** bind Entra admins and readers at bootstrap and emit an Entra kubeconfig ([#8](https://github.com/pelotech/terraform-rke2-foundation/issues/8)) ([26abeb2](https://github.com/pelotech/terraform-rke2-foundation/commit/26abeb2b5a0b63e47b8ea9d262d8d1c37ade92ea))


### Bug Fixes

* **azure:** remove a server's NIC from its pools and NSG only after the VM is gone ([#11](https://github.com/pelotech/terraform-rke2-foundation/issues/11)) ([566ef4c](https://github.com/pelotech/terraform-rke2-foundation/commit/566ef4c10fd9029b425c796204ce3d1bab26d039))
* **azure:** return the cluster endpoint only once the nodes exist ([#15](https://github.com/pelotech/terraform-rke2-foundation/issues/15)) ([6899d2c](https://github.com/pelotech/terraform-rke2-foundation/commit/6899d2c22b6db0b1fa4af941af8af4f7e68d0172))
* **azure:** write a server NIC's NSG association after its pool associations ([#12](https://github.com/pelotech/terraform-rke2-foundation/issues/12)) ([0f6d509](https://github.com/pelotech/terraform-rke2-foundation/commit/0f6d50914faf2139e7986832e2a396e1082c8657))
* **bootstrap:** derive the node password from the name and the agent token ([#14](https://github.com/pelotech/terraform-rke2-foundation/issues/14)) ([da410e8](https://github.com/pelotech/terraform-rke2-foundation/commit/da410e888f72b2e062912b9f6fa26985f024bcdb))
* **bootstrap:** install the iptables modules RHEL 10 ships apart ([#10](https://github.com/pelotech/terraform-rke2-foundation/issues/10)) ([9e50f0b](https://github.com/pelotech/terraform-rke2-foundation/commit/9e50f0b445f778f9b89d69cce9b72edded44d6ce))
* **bootstrap:** install the iptables modules RHEL 10 ships apart ([#9](https://github.com/pelotech/terraform-rke2-foundation/issues/9)) ([3c60624](https://github.com/pelotech/terraform-rke2-foundation/commit/3c60624106a0620cb448725bc1f09da6aca02493))
* **bootstrap:** label the host directories kube-ovn writes for SELinux ([#13](https://github.com/pelotech/terraform-rke2-foundation/issues/13)) ([e6a843e](https://github.com/pelotech/terraform-rke2-foundation/commit/e6a843e4482f23e43046c59e0c77ab5bb14e9e36))
* **examples:** pin cni-bootstrap to v1.1.0 ([#16](https://github.com/pelotech/terraform-rke2-foundation/issues/16)) ([dbed42d](https://github.com/pelotech/terraform-rke2-foundation/commit/dbed42d74d86eeb043f597e4006d73d8fc5ab752))


### Docs

* create the admin kubeconfig with mode 0600 ([#7](https://github.com/pelotech/terraform-rke2-foundation/issues/7)) ([3a7e518](https://github.com/pelotech/terraform-rke2-foundation/commit/3a7e518e4182cef2b371777a6f9ddcfe2cee50b8))
* give the host notes their own sections and point the module README at the runbook ([#17](https://github.com/pelotech/terraform-rke2-foundation/issues/17)) ([f152505](https://github.com/pelotech/terraform-rke2-foundation/commit/f152505651119e4ae7849ca7ad7c9f8170d88c8e))
