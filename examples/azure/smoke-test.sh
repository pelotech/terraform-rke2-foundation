#!/usr/bin/env bash
# Acceptance checks for the example cluster: every node Ready, a LoadBalancer Service gets an address
# from cloud-provider-azure, a disk PVC binds and mounts through the CSI driver. Needs kubectl and
# KUBECONFIG pointing at the kubeconfig output. Pass --keep to leave the test namespace in place.
set -euo pipefail
: "${KUBECONFIG:?set KUBECONFIG to the file holding the kubeconfig output}"
ns=rke2-smoke

echo "--- nodes ---"
kubectl wait --for=condition=Ready nodes --all --timeout=900s
kubectl get nodes -o wide

kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ns" apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers: [{ name: web, image: nginx:1.27-alpine, ports: [{ containerPort: 80 }] }]
---
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  type: LoadBalancer
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: rke2-smoke-disk }
provisioner: disk.csi.azure.com
parameters: { skuName: StandardSSD_LRS }
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: rke2-smoke-disk
  resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: w
      image: busybox:1.36
      command: [sh, -c, "echo ok > /data/probe && sleep 3600"]
      volumeMounts: [{ name: data, mountPath: /data }]
  volumes: [{ name: data, persistentVolumeClaim: { claimName: data } }]
EOF

echo "--- LoadBalancer Service: waiting for an address from cloud-provider-azure ---"
for _ in $(seq 1 90); do
  ip=$(kubectl -n "$ns" get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$ip" ] && break
  sleep 10
done
[ -n "${ip:-}" ] || { echo "no load balancer address after 15 minutes" >&2; kubectl -n "$ns" describe svc web | tail -15; exit 1; }
echo "service address: $ip"
if curl -sf --max-time 10 "http://$ip/" >/dev/null; then echo "http through the service: ok"; else echo "http through the service: not reachable from here (private address or firewall); the address itself is the cloud provider's work"; fi

echo "--- disk PVC: waiting for the CSI driver to bind and mount ---"
kubectl -n "$ns" wait --for=condition=Ready pod/writer --timeout=600s
kubectl -n "$ns" get pvc data -o custom-columns='PVC:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName'
kubectl -n "$ns" exec writer -- cat /data/probe

if [ "${1:-}" != "--keep" ]; then
  kubectl delete namespace "$ns" --wait=false >/dev/null
  echo "cleaned up namespace $ns"
fi
echo "smoke test passed"
