#!/usr/bin/env bash
# Uploads each new etcd snapshot of this server once, through put_snapshot from put-snapshot.sh.
# Runs from rke2-foundation-snapshots.timer. A marker per uploaded file keeps it idempotent.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/rke2-foundation/env
LIB_DIR=$(dirname "$0")
SNAPSHOT_DIR=/var/lib/rancher/rke2/server/db/snapshots
MARK_DIR=/var/lib/rke2-foundation/uploaded-snapshots
NODE=$(hostname)

log() { echo "rke2-foundation-snapshots: $*"; }

# shellcheck source=/dev/null
. "$LIB_DIR/put-snapshot.sh"

[ -d "$SNAPSHOT_DIR" ] || exit 0
install -d -m 0700 "$MARK_DIR"
for f in "$SNAPSHOT_DIR"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  [ -e "$MARK_DIR/$name" ] && continue
  # RKE2 may still be writing the newest file.
  [ $(( $(date +%s) - $(stat -c %Y "$f") )) -ge 120 ] || continue
  put_snapshot "$CLUSTER_NAME/$NODE/$name" "$f"
  touch "$MARK_DIR/$name"
  log "uploaded $name"
done
# Forget the markers of snapshots RKE2 has pruned.
for m in "$MARK_DIR"/*; do
  [ -e "$m" ] || continue
  [ -e "$SNAPSHOT_DIR/$(basename "$m")" ] || rm -f "$m"
done
