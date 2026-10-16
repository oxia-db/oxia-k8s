# k3s on Oxia

k3s keeps its state in Oxia, through the oxia-etcd gateway, on one machine with Docker Compose:

```
k3s ──etcd API──▶ oxia-etcd-0 (serving)   ┐
                  oxia-etcd-1 (standby)   ┘──▶ Oxia: 3 data servers, 3 coordinators (Raft)
```

- **Oxia** runs without Kubernetes: its coordinators keep the cluster metadata in Raft. `oxia-init` registers the
  data servers and the `kubernetes` namespace with `oxia admin`.
- **oxia-etcd**: one gateway serves the records, the other stands by with its etcd port closed, and takes over when
  the first one stops.
- **k3s** is given both gateways as its `--datastore-endpoint`.

## Run it

```sh
docker compose up -d
export KUBECONFIG=$PWD/output/kubeconfig.yaml
kubectl get nodes
kubectl create deployment web --image=nginx --replicas=2
```

The images default to `oxia/oxia:nightly-beta`, `oxia/oxia-etcd:nightly` and `rancher/k3s:v1.37.1-k3s1`. Override them
with `OXIA_IMAGE`, `OXIA_ETCD_IMAGE` and `K3S_IMAGE`, e.g. with a gateway built from source:

```sh
docker build -t oxia/oxia-etcd:dev ../../../oxia-etcd   # a checkout of oxia-etcd
OXIA_ETCD_IMAGE=oxia/oxia-etcd:dev docker compose up -d
```

## Fail over the gateway

Stop the gateway that serves (the one that logged `Serving the etcd API`):

```sh
docker compose logs oxia-etcd-0 oxia-etcd-1 | grep "Serving the etcd API"
docker compose stop oxia-etcd-0
kubectl scale deployment web --replicas=4
```

The standby takes over within a second. k3s reconnects to it, and the API serves writes again after about ten
seconds; k3s may restart once when its controllers lose their leases in between.

## Clean up

```sh
docker compose down -v
```

## Notes

- `oxia/oxia:nightly-beta`, because the 0.17.1 coordinators can't restart with Raft metadata: they fail with
  `panic: metadata bad version`. The fix is on Oxia's main branch.
- k3s has a fixed hostname and address, so that its node keeps them across restarts.
- k3s needs free disk space: under 10-15% free, the kubelet taints the node with `disk-pressure` and no pod starts.
