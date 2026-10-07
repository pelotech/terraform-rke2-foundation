#!/usr/bin/env bash
# Renews this node's RKE2 certificates when rke2 certificate check reports one inside the renewal window.
# An agent restarts its service. A server rotates its keys and restarts, one server at a time through a
# Lease in kube-system. RENEW_FORCE=true skips the check, for a drill.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/rke2-foundation/env
export PATH="$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin"
LEASE=rke2-foundation-certificate-renewal
LEASE_SECONDS=3600
NODE=$(hostname)

log() { echo "rke2-foundation-renew: $*"; }

due() {
  rke2 certificate check --output json 2>/dev/null \
    | python3 -c 'import json, sys; print(sum(1 for c in json.load(sys.stdin)["Certificates"] if c["Status"] != "OK"))'
}

if [ "${RENEW_FORCE:-false}" != true ]; then
  count=$(due)
  if [ "$count" = 0 ]; then
    exit 0
  fi
  log "$count certificates inside the renewal window"
fi

if [ "$ROLE" = agent ]; then
  log "restarting rke2-agent"
  systemctl restart rke2-agent.service
  exit 0
fi

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
# Every server must be Ready before this one leaves.
not_ready=$(kubectl get nodes -l node-role.kubernetes.io/control-plane=true -o json \
  | python3 -c 'import json, sys; print(sum(1 for n in json.load(sys.stdin)["items"] if not any(c["type"] == "Ready" and c["status"] == "True" for c in n["status"]["conditions"])))')
if [ "$not_ready" != 0 ]; then
  log "$not_ready server nodes are not Ready, trying again on the next run"
  exit 0
fi

# Lease times are MicroTime, hence the fraction.
now=$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)
lease="apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: $LEASE
  namespace: kube-system
spec:
  holderIdentity: $NODE
  acquireTime: \"$now\"
  renewTime: \"$now\"
  leaseDurationSeconds: $LEASE_SECONDS"
if ! printf '%s\n' "$lease" | kubectl create -f - >/dev/null 2>&1; then
  holder=$(kubectl -n kube-system get lease "$LEASE" -o jsonpath='{.spec.holderIdentity}')
  renewed=$(kubectl -n kube-system get lease "$LEASE" -o jsonpath='{.spec.renewTime}')
  if [ $(( $(date -u +%s) - $(date -u -d "$renewed" +%s) )) -lt "$LEASE_SECONDS" ]; then
    log "$holder holds the lease, trying again on the next run"
    exit 0
  fi
  # A lease older than its duration belongs to a run that died.
  kubectl -n kube-system delete lease "$LEASE" >/dev/null
  printf '%s\n' "$lease" | kubectl create -f - >/dev/null
fi

log "rotating the certificates of $NODE"
systemctl stop rke2-server.service
rke2 certificate rotate
systemctl start rke2-server.service
deadline=$((SECONDS + 600))
until kubectl get --raw /readyz >/dev/null 2>&1; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    log "the API did not answer within 10 minutes; the lease expires on its own"
    exit 1
  fi
  sleep 5
done
kubectl -n kube-system delete lease "$LEASE" >/dev/null
log "done"
