#!/usr/bin/env bash
# Installs RKE2 and bootstraps or joins the cluster. /etc/rke2-foundation/env supplies ROLE,
# INIT_CANDIDATE, REGISTRATION_ADDRESS, RKE2_VERSION, INSTALL_URL, BOOTSTRAP_WAIT_SECONDS, CIS_PROFILE,
# DISABLE_FIREWALLD, ETCD_DISK_DEVICE, SELINUX_CONTAINER_DIRS and SECRETS, the name=path pairs that
# fetch-secrets.sh writes under SECRET_DIR.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/rke2-foundation/env
LIB_DIR=$(dirname "$0")
SECRET_DIR=/run/rke2-foundation/secrets
DATA_DIR=/var/lib/rancher/rke2
CONF_DIR=/etc/rancher/rke2/config.yaml.d

log() { echo "rke2-foundation: $*"; }

install -d -m 0700 "$SECRET_DIR" "$CONF_DIR"
# shellcheck source=/dev/null
. "$LIB_DIR/fetch-secrets.sh"
for pair in $SECRETS; do
  fetch "${pair%%=*}" "${pair#*=}"
done

if [ "$ROLE" = server ] && [ -n "$ETCD_DISK_DEVICE" ]; then
  # The data disk attaches after the VM boots, so wait for it; a fresh disk gets a filesystem.
  deadline=$((SECONDS + 600))
  until [ -b "$ETCD_DISK_DEVICE" ]; do
    [ "$SECONDS" -lt "$deadline" ] || { log "no block device at $ETCD_DISK_DEVICE after 10 minutes"; exit 1; }
    sleep 5
  done
  if ! blkid "$ETCD_DISK_DEVICE" >/dev/null 2>&1; then
    mkfs.xfs -q -L rke2-etcd "$ETCD_DISK_DEVICE"
  fi
  install -d -m 0700 "$DATA_DIR/server/db"
  grep -q " $DATA_DIR/server/db " /etc/fstab || printf 'LABEL=rke2-etcd %s xfs defaults,nofail 0 2\n' "$DATA_DIR/server/db" >> /etc/fstab
  mountpoint -q "$DATA_DIR/server/db" || mount "$DATA_DIR/server/db"
fi

if [ "$ROLE" = server ]; then
  # RKE2 adopts a CA set that exists in its TLS directory before first start.
  install -d -m 0700 "$DATA_DIR/server/tls"
  cp -a "$SECRET_DIR/tls/." "$DATA_DIR/server/tls/"
  {
    printf 'token: %s\n' "$(cat "$SECRET_DIR/token")"
    printf 'agent-token: %s\n' "$(cat "$SECRET_DIR/agent-token")"
  } > "$CONF_DIR/10-token.yaml"
else
  printf 'token: %s\n' "$(cat "$SECRET_DIR/agent-token")" > "$CONF_DIR/10-token.yaml"
fi
chmod 0600 "$CONF_DIR/10-token.yaml"

# A node that comes back with its name, as a reimaged scale set instance does, must present the node password the
# server stored for that name, or the server rejects it. Derived from the name and the agent token, it stays the same.
install -d -m 0700 /etc/rancher/node
printf '%s:%s' "$(hostname)" "$(cat "$SECRET_DIR/agent-token")" | sha256sum | cut -c1-64 > /etc/rancher/node/password
chmod 0600 /etc/rancher/node/password
rm -rf "$SECRET_DIR"

if [ "$CIS_PROFILE" = true ] && ! id etcd >/dev/null 2>&1; then
  useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U
fi

# RHEL-family images ship nm-cloud-setup, whose routing rules break the CNI; RKE2 documents disabling it.
for unit in nm-cloud-setup.service nm-cloud-setup.timer; do
  if systemctl cat "$unit" >/dev/null 2>&1; then
    systemctl disable --now "$unit"
  fi
done

# RKE2 documents firewalld as incompatible with its networking; a hardened image can keep it with its own rules.
if [ "$DISABLE_FIREWALLD" = true ] && systemctl is-enabled firewalld.service >/dev/null 2>&1; then
  systemctl disable --now firewalld.service
fi

# SELinux lets a pod that runs as container_t write container_file_t only. A file context rule survives a relabel,
# and /run is empty at boot, so a tmpfiles entry creates those directories again with the same label.
if [ -n "$SELINUX_CONTAINER_DIRS" ] && selinuxenabled 2>/dev/null; then
  rm -f /etc/tmpfiles.d/rke2-foundation.conf
  for dir in $SELINUX_CONTAINER_DIRS; do
    semanage fcontext -a -t container_file_t "$dir(/.*)?" 2>/dev/null || semanage fcontext -m -t container_file_t "$dir(/.*)?"
    case "$dir" in
      /run/*) printf 'd %s 0755 root root -\n' "$dir" >> /etc/tmpfiles.d/rke2-foundation.conf ;;
    esac
    install -d "$dir"
    restorecon -R "$dir"
  done
fi

# Two reasons. RHEL 10 moved the iptables modules that kube-proxy and the CNI need into kernel-modules-extra, which
# the Azure Marketplace image lacks. And the RKE2 RPM requires that package but dnf resolves it to the newest kernel,
# which runs only after a reboot; the running kernel's build loads now and pulls no second kernel.
if command -v dnf >/dev/null 2>&1 && ! modprobe -n nft_compat >/dev/null 2>&1; then
  dnf install -y "kernel-modules-extra-$(uname -r)"
fi

log "installing RKE2 $RKE2_VERSION as $ROLE"
curl -sfL "$INSTALL_URL" | INSTALL_RKE2_VERSION="$RKE2_VERSION" INSTALL_RKE2_TYPE="$ROLE" sh -

if [ "$CIS_PROFILE" = true ]; then
  for f in /usr/local/share/rke2/rke2-cis-sysctl.conf /usr/share/rke2/rke2-cis-sysctl.conf; do
    if [ -f "$f" ]; then
      cp -f "$f" /etc/sysctl.d/60-rke2-cis.conf
      break
    fi
  done
  systemctl restart systemd-sysctl
fi

# A 200 from the supervisor's /ping, not a bare TCP connect: a balancer may accept and then close.
registration_answers() {
  [ "$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "https://$REGISTRATION_ADDRESS:9345/ping")" = 200 ]
}

rm -f "$CONF_DIR/00-join.yaml"
join=true
if [ "$ROLE" = server ] && [ "$INIT_CANDIDATE" = true ]; then
  # Bootstrap a new cluster only when nothing answers on the registration address.
  join=false
  deadline=$((SECONDS + BOOTSTRAP_WAIT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if registration_answers; then
      join=true
      break
    fi
    sleep 5
  done
else
  until registration_answers; do
    log "waiting for $REGISTRATION_ADDRESS:9345"
    sleep 5
  done
fi

if [ "$join" = true ]; then
  printf 'server: https://%s:9345\n' "$REGISTRATION_ADDRESS" > "$CONF_DIR/00-join.yaml"
  log "joining through $REGISTRATION_ADDRESS"
else
  log "bootstrapping a new cluster"
fi

systemctl enable --now "rke2-$ROLE.service"

if [ "$ROLE" = server ]; then
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  export PATH="$PATH:$DATA_DIR/bin"
  until kubectl get --raw /readyz >/dev/null 2>&1; do
    sleep 5
  done
  if [ -s "$LIB_DIR/post-bootstrap.sh" ]; then
    bash "$LIB_DIR/post-bootstrap.sh"
  fi
fi
for timer in renew snapshots; do
  if [ -s "/etc/systemd/system/rke2-foundation-$timer.timer" ]; then
    systemctl enable --now "rke2-foundation-$timer.timer"
  fi
done
log "done"
