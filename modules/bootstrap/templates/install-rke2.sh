#!/usr/bin/env bash
# Installs a pinned release before bootstrap.sh starts any RKE2 service.
set -euo pipefail
: "${ROLE:?}" "${RKE2_VERSION:?}" "${INSTALL_URL:?}"
INSTALL_ARTIFACT_PATH=${INSTALL_ARTIFACT_PATH:-}

fail() { echo "rke2-foundation: $*" >&2; exit 1; }

if [ -n "$INSTALL_ARTIFACT_PATH" ] && [ ! -f "$INSTALL_ARTIFACT_PATH/install.sh" ]; then
  fail "missing offline installer at $INSTALL_ARTIFACT_PATH/install.sh"
fi

# RHEL 10 puts the iptables modules in a package for the running kernel. Offline images
# must already contain it; never fall back to an RPM repository when assets are local.
if command -v dnf >/dev/null 2>&1 && ! modprobe -n nft_compat >/dev/null 2>&1; then
  if [ -n "$INSTALL_ARTIFACT_PATH" ]; then
    fail "offline image is missing the nft_compat kernel module for $(uname -r)"
  fi
  dnf install -y "kernel-modules-extra-$(uname -r)"
fi

if [ -n "$INSTALL_ARTIFACT_PATH" ]; then
  INSTALL_RKE2_METHOD=tar INSTALL_RKE2_ARTIFACT_PATH="$INSTALL_ARTIFACT_PATH" \
    INSTALL_RKE2_VERSION="$RKE2_VERSION" INSTALL_RKE2_TYPE="$ROLE" \
    sh "$INSTALL_ARTIFACT_PATH/install.sh"
else
  curl -sfL "$INSTALL_URL" | INSTALL_RKE2_VERSION="$RKE2_VERSION" INSTALL_RKE2_TYPE="$ROLE" sh -
fi

# The upstream offline installer checks local checksums but does not tie the tarball
# to INSTALL_RKE2_VERSION. Reject a stale image before any node can join the cluster.
# Tar installs can use /opt/rke2 when /usr/local is read-only or a mount point.
# Inspect the installed service, so PATH cannot select a missing or stale binary.
service_exec=$(systemctl show --property=ExecStart --value "rke2-$ROLE")
rke2_binary=${service_exec#*path=}
rke2_binary=${rke2_binary%% *}
[[ "$rke2_binary" = /* && -x "$rke2_binary" ]] || fail "cannot locate installed rke2-$ROLE service binary"
actual_version=$("$rke2_binary" --version | awk 'NR == 1 { print $3 }')
[ "$actual_version" = "$RKE2_VERSION" ] || fail "installed RKE2 version $actual_version does not match $RKE2_VERSION"
