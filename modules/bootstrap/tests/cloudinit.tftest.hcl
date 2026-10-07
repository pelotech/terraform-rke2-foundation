# cloud-init for the init candidate, the other servers and each agent pool.

run "roles" {
  command = plan
  variables {
    agent_pools           = { default = {} }
    server_manifests      = { "cloud-provider.yaml" = "kind: HelmChart\n" }
    post_bootstrap_script = "echo done"
  }
  assert {
    condition     = startswith(output.server_user_data.init_candidate, "#cloud-config\n") && startswith(output.server_user_data.member, "#cloud-config\n") && startswith(output.agent_user_data["default"], "#cloud-config\n")
    error_message = "every role renders cloud-config"
  }
  assert {
    condition     = strcontains(output.server_user_data.init_candidate, "INIT_CANDIDATE=true") && strcontains(output.server_user_data.member, "INIT_CANDIDATE=false") && strcontains(output.agent_user_data["default"], "INIT_CANDIDATE=false")
    error_message = "only the init candidate may bootstrap a new cluster"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "ROLE=server") && strcontains(output.agent_user_data["default"], "ROLE=agent")
    error_message = "the role drives the install type and the join flow"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "REGISTRATION_ADDRESS=10.0.0.4") && strcontains(output.server_user_data.member, "RKE2_VERSION=v1.36.5+rke2r1") && strcontains(output.server_user_data.member, "BOOTSTRAP_WAIT_SECONDS=90") && strcontains(output.server_user_data.member, "INSTALL_URL=https://get.rke2.io") && strcontains(output.server_user_data.member, "CIS_PROFILE=false")
    error_message = "the env file carries every setting bootstrap.sh reads"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "rke2-tls-service-key=tls/service.key") && strcontains(output.server_user_data.member, "rke2-token=token") && strcontains(output.agent_user_data["default"], "SECRETS=\"rke2-agent-token=agent-token\"")
    error_message = "each role lists the secrets it fetches"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "/var/lib/rancher/rke2/server/manifests/cloud-provider.yaml") && !strcontains(output.agent_user_data["default"], "server/manifests")
    error_message = "manifests go to servers only"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "echo server") && strcontains(output.agent_user_data["default"], "echo agent") && !strcontains(output.agent_user_data["default"], "echo server")
    error_message = "each role embeds its own fetch script"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "echo done") && !strcontains(output.agent_user_data["default"], "\"path\": \"/usr/local/lib/rke2-foundation/post-bootstrap.sh\"")
    error_message = "the post-bootstrap script is a server file"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "/etc/rancher/rke2/config.yaml") && strcontains(output.server_user_data.member, "cluster-cidr") && !strcontains(output.agent_user_data["default"], "cluster-cidr")
    error_message = "config.yaml holds the server config on servers and the agent config on agents"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "/usr/local/lib/rke2-foundation/bootstrap.sh") && strcontains(output.server_user_data.member, "INSTALL_RKE2_TYPE")
    error_message = "bootstrap.sh is embedded and runs the RKE2 install script"
  }
}

run "agent_user_data_follows_pools" {
  command = plan
  variables {
    agent_pools = { general = {}, gpu = { taints = ["nvidia.com/gpu=true:NoSchedule"] } }
  }
  assert {
    condition     = sort(keys(output.agent_user_data)) == tolist(["general", "gpu"])
    error_message = "one cloud-init per pool"
  }
  assert {
    condition     = strcontains(output.agent_user_data["gpu"], "nvidia.com/gpu=true:NoSchedule") && !strcontains(output.agent_user_data["general"], "nvidia.com")
    error_message = "a pool's taints render only into its own config"
  }
}

run "renewal_timer_ships_by_default" {
  command = plan
  variables {
    agent_pools = { default = {} }
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "DISABLE_FIREWALLD=true") && strcontains(output.server_user_data.member, "/usr/local/lib/rke2-foundation/renew-certificates.sh") && strcontains(output.server_user_data.member, "ExecStart=/usr/local/lib/rke2-foundation/renew-certificates.sh") && strcontains(output.agent_user_data["default"], "/etc/systemd/system/rke2-foundation-renew.timer")
    error_message = "every node gets the renewal script, service and timer, and the env file carries the firewalld switch"
  }
}

run "renewal_timer_off" {
  command = plan
  variables {
    agent_pools         = { default = {} }
    certificate_renewal = false
    disable_firewalld   = false
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "DISABLE_FIREWALLD=false") && !strcontains(output.server_user_data.member, "/usr/local/lib/rke2-foundation/renew-certificates.sh") && !strcontains(output.agent_user_data["default"], "/etc/systemd/system/rke2-foundation-renew.timer")
    error_message = "certificate_renewal = false ships no renewal files; disable_firewalld reaches the env file"
  }
}

run "etcd_disk_device_reaches_the_env_file" {
  command = plan
  variables {
    etcd_disk_device = "/dev/disk/azure/scsi1/lun0"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "ETCD_DISK_DEVICE=/dev/disk/azure/scsi1/lun0")
    error_message = "the server env file names the etcd disk device"
  }
}

run "etcd_on_the_root_disk_by_default" {
  command = plan
  assert {
    condition     = strcontains(output.server_user_data.member, "ETCD_DISK_DEVICE=\n")
    error_message = "no device by default: etcd stays on the root disk"
  }
}

run "snapshot_upload_timer_with_a_put_script" {
  command = plan
  variables {
    agent_pools         = { default = {} }
    put_snapshot_script = "put_snapshot() { cp \"$2\" \"/var/tmp/$1\"; }"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "/usr/local/lib/rke2-foundation/put-snapshot.sh") && strcontains(output.server_user_data.member, "ExecStart=/usr/local/lib/rke2-foundation/upload-snapshots.sh") && strcontains(output.server_user_data.member, "/etc/systemd/system/rke2-foundation-snapshots.timer") && !strcontains(output.agent_user_data["default"], "upload-snapshots.sh")
    error_message = "servers get the put script, the upload loop, its service and timer; agents get none"
  }
}

run "no_snapshot_upload_by_default" {
  command = plan
  assert {
    condition     = !strcontains(output.server_user_data.member, "/usr/local/lib/rke2-foundation/upload-snapshots.sh") && strcontains(output.server_user_data.member, "CLUSTER_NAME=platformdev")
    error_message = "no upload files without a put script; the env file carries the cluster name"
  }
}
