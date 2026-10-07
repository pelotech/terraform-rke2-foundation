#!/usr/bin/env bash
# Local bring-up of the RKE2 bootstrap on Multipass VMs. See README.md.
#   ./run.sh up [cilium|kube-ovn]   launch the VMs, configure haproxy, render and stage cloud-init, wait for registration
#   ./run.sh cni                    install the CNI through cni-bootstrap and wait for Ready
#   ./run.sh status                 list the nodes
#   ./run.sh down                   delete the VMs and the generated files
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
stage="$here/stage"
export KUBECONFIG="$stage/kubeconfig"
servers="server-0 server-1 server-2"

ip_of() { multipass info "$1" --format json | python3 -c 'import json,sys; d=json.load(sys.stdin)["info"]; print(list(d.values())[0]["ipv4"][0])'; }

launch() { # name cpus memory
  multipass info "$1" >/dev/null 2>&1 || multipass launch 26.04 --name "$1" --cpus "$2" --memory "$3" --disk 20G >/dev/null
}

configure_lb() {
  local api="" sup=""
  for s in $servers; do
    api="$api  server $s $(ip_of "$s"):6443 check inter 2s fall 2 rise 1"$'\n'
    sup="$sup  server $s $(ip_of "$s"):9345 check inter 2s fall 2 rise 1"$'\n'
  done
  python3 - "$here" "$api" "$sup" <<'PY'
import sys
here, api, sup = sys.argv[1], sys.argv[2].rstrip("\n"), sys.argv[3].rstrip("\n")
t = open(f"{here}/haproxy.cfg.tmpl").read().replace("__API_SERVERS__", api).replace("__SUPERVISOR_SERVERS__", sup)
open(f"{here}/stage/haproxy.cfg", "w").write(t)
PY
  multipass exec lb -- sudo bash -c 'command -v haproxy >/dev/null || (DEBIAN_FRONTEND=noninteractive apt-get -qq update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y haproxy >/dev/null)'
  multipass transfer "$stage/haproxy.cfg" lb:/tmp/haproxy.cfg
  multipass exec lb -- sudo bash -c 'install -m 0644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null && systemctl restart haproxy'
}

render() { # cni
  (cd "$here" && terraform init -input=false -no-color >/dev/null && terraform apply -input=false -auto-approve -no-color -var "registration_address=$(ip_of lb)" -var "cni=$1" >/dev/null && terraform output -json > "$stage/outputs.json")
  python3 - "$stage" <<'PY'
import json, os, sys
stage = sys.argv[1]
o = {k: v["value"] for k, v in json.load(open(f"{stage}/outputs.json")).items()}
open(f"{stage}/server_init.yaml", "w").write(o["server_user_data"]["init_candidate"])
open(f"{stage}/server_member.yaml", "w").write(o["server_user_data"]["member"])
for pool, data in o["agent_user_data"].items():
    open(f"{stage}/agent_{pool}.yaml", "w").write(data)
def seed(dirname, paths):
    for name, path in paths.items():
        full = f"{stage}/{dirname}/{path}"
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as fh:
            fh.write(o["server_secret_contents"][name])
        os.chmod(full, 0o600)
seed("seed-server", o["server_secret_paths"])
seed("seed-agent", o["agent_secret_paths"])
open(f"{stage}/kubeconfig", "w").write(o["kubeconfig"])
os.chmod(f"{stage}/kubeconfig", 0o600)
PY
}

stage_node() { # vm user-data seed-dir
  multipass transfer "$2" "$1:/tmp/user-data.yaml"
  multipass transfer "$here/apply-cloud-config.py" "$1:/tmp/apply-cloud-config.py"
  multipass exec "$1" -- sudo rm -rf /tmp/rke2-seed
  multipass transfer -r "$3" "$1:/tmp/rke2-seed"
  multipass exec "$1" -- sudo bash -c "chmod -R go-rwx /tmp/rke2-seed && python3 /tmp/apply-cloud-config.py /tmp/user-data.yaml && systemd-run --quiet --unit=rke2-foundation-$(date +%s) -p StandardOutput=append:/var/log/rke2-foundation.log -p StandardError=append:/var/log/rke2-foundation.log bash /usr/local/lib/rke2-foundation/bootstrap.sh"
  echo "$1: bootstrap started"
}

wait_log() { # vm
  for _ in $(seq 1 120); do
    multipass exec "$1" -- sudo grep -qE 'rke2-foundation: done' /var/log/rke2-foundation.log 2>/dev/null && return 0
    multipass exec "$1" -- sudo grep -qE 'could not|no block device|No such file|command not found' /var/log/rke2-foundation.log 2>/dev/null && { multipass exec "$1" -- sudo tail -5 /var/log/rke2-foundation.log; return 1; }
    sleep 10
  done
  echo "$1: no result after 20 minutes" >&2
  return 1
}

case "${1:-}" in
  up)
    cni="${2:-kube-ovn}"
    mkdir -p "$stage"
    echo "$cni" > "$stage/profile"
    launch lb 1 1G &
    for s in $servers; do launch "$s" 3 4G & done
    launch agent 2 3G &
    if [ "$cni" = kube-ovn ]; then launch cni 4 6G & fi
    wait
    configure_lb
    render "$cni"
    stage_node server-0 "$stage/server_init.yaml" "$stage/seed-server"
    stage_node server-1 "$stage/server_member.yaml" "$stage/seed-server"
    stage_node server-2 "$stage/server_member.yaml" "$stage/seed-server"
    stage_node agent "$stage/agent_general.yaml" "$stage/seed-agent"
    if [ "$cni" = kube-ovn ]; then stage_node cni "$stage/agent_cni.yaml" "$stage/seed-agent"; fi
    for vm in $servers agent; do wait_log "$vm"; done
    if [ "$cni" = kube-ovn ]; then wait_log cni; fi
    kubectl get nodes
    ;;
  cni)
    cni=$(cat "$stage/profile")
    lb_ip=$(ip_of lb)
    python3 - "$stage" "$cni" "$lb_ip" <<'PY'
import json, sys
stage, cni, lb_ip = sys.argv[1], sys.argv[2], sys.argv[3]
o = {k: v["value"] for k, v in json.load(open(f"{stage}/outputs.json")).items()}
tfvars = {"cni": cni, "endpoint": f"https://{lb_ip}:6443", "ca": o["cluster_ca_certificate"], "cert": o["admin_client_certificate"], "key": o["admin_client_key"], "cni_node_size": o["cni_node_size"], "cni_node_selector": o["cni_node_selector"]}
json.dump(tfvars, open(f"{stage}/../cni/terraform.tfvars.json", "w"))
PY
    (cd "$here/cni" && terraform init -input=false -no-color >/dev/null && terraform apply -input=false -auto-approve -no-color | grep -E 'Apply complete|Error')
    kubectl wait --for=condition=Ready nodes --all --timeout=900s
    kubectl get nodes
    ;;
  status)
    kubectl get nodes -o wide
    ;;
  down)
    for vm in lb $servers agent cni; do multipass delete --purge "$vm" 2>/dev/null || true; done
    find "${stage:?}" -mindepth 1 -not -name .gitkeep -delete
    rm -f "${here:?}/terraform.tfstate" "${here:?}/terraform.tfstate.backup" "${here:?}/cni/terraform.tfstate" "${here:?}/cni/terraform.tfstate.backup" "${here:?}/cni/terraform.tfvars.json"
    echo "deleted"
    ;;
  *)
    sed -n '2,6p' "$0"
    exit 1
    ;;
esac
