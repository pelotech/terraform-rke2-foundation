locals {
  lib_dir = "/usr/local/lib/rke2-foundation"

  node_roles = merge(
    {
      init_candidate = { role = "server", init_candidate = true, config = local.server_config }
      member         = { role = "server", init_candidate = false, config = local.server_config }
    },
    { for pool, config in local.agent_config : "agent_${pool}" => { role = "agent", init_candidate = false, config = config } },
  )

  env_files = {
    for key, spec in local.node_roles : key => join("\n", [
      "ROLE=${spec.role}",
      "CLUSTER_NAME=${var.name}",
      "INIT_CANDIDATE=${spec.init_candidate}",
      "REGISTRATION_ADDRESS=${var.registration_address}",
      "RKE2_VERSION=${var.rke2_version}",
      "INSTALL_URL=${var.install_script_url}",
      "BOOTSTRAP_WAIT_SECONDS=${var.bootstrap_wait_seconds}",
      "CIS_PROFILE=${var.cis_profile}",
      "DISABLE_FIREWALLD=${var.disable_firewalld}",
      "SELINUX_CONTAINER_DIRS=\"${join(" ", var.selinux_container_dirs)}\"",
      "ETCD_DISK_DEVICE=${var.etcd_disk_device == null ? "" : var.etcd_disk_device}",
      # Quoted: the pairs are space separated and the file is sourced by bash.
      "SECRETS=\"${join(" ", [for name, path in(spec.role == "server" ? local.server_secret_paths : local.agent_secret_paths) : "${name}=${path}"])}\"",
    ])
  }

  # Each optional script ships with its oneshot service and timer; bootstrap.sh enables a timer when its script exists.
  timers = {
    renew = {
      description = "Renew the RKE2 certificates of this node when they near expiry"
      on_calendar = "daily"
      delay       = "6h"
      roles       = var.certificate_renewal ? ["server", "agent"] : []
    }
    snapshots = {
      description = "Upload the new RKE2 etcd snapshots of this node"
      on_calendar = "hourly"
      delay       = "10m"
      roles       = var.put_snapshot_script == "" ? [] : ["server"]
    }
  }
  timer_scripts = { renew = "renew-certificates.sh", snapshots = "upload-snapshots.sh" }
  timer_files = {
    for role in ["server", "agent"] : role => flatten([
      for name, timer in local.timers : [
        { path = "${local.lib_dir}/${local.timer_scripts[name]}", permissions = "0700", content = file("${path.module}/templates/${local.timer_scripts[name]}") },
        { path = "/etc/systemd/system/rke2-foundation-${name}.service", permissions = "0644", content = templatefile("${path.module}/templates/oneshot.service.tftpl", { description = timer.description, exec_start = "${local.lib_dir}/${local.timer_scripts[name]}" }) },
        { path = "/etc/systemd/system/rke2-foundation-${name}.timer", permissions = "0644", content = templatefile("${path.module}/templates/timer.tftpl", { description = timer.description, on_calendar = timer.on_calendar, delay = timer.delay }) },
      ] if contains(timer.roles, role)
    ])
  }

  # Secrets never travel here: cloud-init carries names, endpoints and scripts, and fetches the rest.
  user_data = {
    for key, spec in local.node_roles : key => "#cloud-config\n${yamlencode({
      write_files = concat(
        [
          { path = "/etc/rancher/rke2/config.yaml", permissions = "0600", content = yamlencode(spec.config) },
          { path = "/etc/rke2-foundation/env", permissions = "0600", content = local.env_files[key] },
          { path = "${local.lib_dir}/bootstrap.sh", permissions = "0700", content = file("${path.module}/templates/bootstrap.sh") },
          { path = "${local.lib_dir}/fetch-secrets.sh", permissions = "0700", content = var.fetch_secrets_scripts[spec.role] },
        ],
        local.timer_files[spec.role],
        spec.role == "server" ? concat(
          var.post_bootstrap_script == "" ? [] : [{ path = "${local.lib_dir}/post-bootstrap.sh", permissions = "0700", content = var.post_bootstrap_script }],
          var.put_snapshot_script == "" ? [] : [{ path = "${local.lib_dir}/put-snapshot.sh", permissions = "0700", content = var.put_snapshot_script }],
          [for name, yaml in var.server_manifests : { path = "/var/lib/rancher/rke2/server/manifests/${name}", permissions = "0600", content = yaml }],
        ) : [],
      )
      runcmd = [["bash", "${local.lib_dir}/bootstrap.sh"]]
    })}"
  }
}
