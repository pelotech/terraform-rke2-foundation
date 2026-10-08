# Changelog

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
