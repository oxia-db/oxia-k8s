# Kubernetes on Oxia, with Ansible

Ansible playbooks that deploy, on your own machines, an Oxia cluster, the oxia-etcd gateways, and Kubernetes on them:

- [`k3s.yaml`](k3s.yaml): k3s servers and agents, with the gateways as their `--datastore-endpoint`.
- [`kubernetes.yaml`](kubernetes.yaml): Kubernetes with kubeadm, with the gateways as its external etcd, Flannel and
  containerd.

```
API servers ──etcd API──▶ oxia-etcd (serving)  ┐
                          oxia-etcd (standby)  ┘──▶ Oxia: data servers, coordinators (Raft)
```

Every part runs as a systemd service. Oxia runs without Kubernetes: its coordinators keep the cluster metadata in Raft.

| Playbook | Groups of the inventory |
|---|---|
| both ([`oxia.yaml`](oxia.yaml)) | `oxia_coordinators` (3 or 5), `oxia_dataservers`, `oxia_etcd` (one serves, the others stand by) |
| `k3s.yaml` | `k3s_servers`, `k3s_agents` |
| `kubernetes.yaml` | `kubernetes_control_planes`, `kubernetes_workers` |

## Run it

The machines run Ubuntu or Debian, and Ansible reaches them over SSH with `sudo`:

```sh
pip install ansible-core
cp inventory.example.yaml inventory.yaml   # your machines
ansible-playbook k3s.yaml                  # or kubernetes.yaml
export KUBECONFIG=$PWD/output/kubeconfig.yaml
kubectl get nodes
```

Running a playbook again changes only what differs, e.g. a version. The data servers and the gateways restart one at a
time. The settings, such as the versions and the ports, are in [`group_vars/all.yaml`](group_vars/all.yaml). The k3s
token is generated in `credentials/` on the first run.

The playbooks download Oxia, oxia-etcd, k3s and the Kubernetes packages. To use binaries you built instead:

```sh
ansible-playbook k3s.yaml -e oxia_binary=/path/to/oxia -e oxia_etcd_binary=/path/to/oxia-etcd
```

## Try it on one machine

Three [Lima](https://lima-vm.io) VMs, on a network they share, with `bin/oxia` and `bin/oxia-etcd` built for Linux
(see the notes):

```sh
for i in 0 1 2; do
  limactl create --name=oxia-$i --tty=false --cpus=2 --memory=3 --network=lima:user-v2 template:ubuntu-24.04
  limactl start oxia-$i
done
ansible-playbook -i inventory.lima.yaml k3s.yaml -e oxia_binary=$PWD/bin/oxia -e oxia_etcd_binary=$PWD/bin/oxia-etcd
limactl shell oxia-0 sudo k3s kubectl get nodes
```

Delete them with `limactl delete -f oxia-0 oxia-1 oxia-2`.

## Notes

- **The Oxia version**: the 0.17.1 coordinators can't restart with Raft metadata (`panic: metadata bad version`). The
  fix is on Oxia's main branch: until a release has it, build `oxia` from it and pass `oxia_binary`.
- **oxia-etcd** has no release yet: build it with `CGO_ENABLED=0 GOOS=linux go build -o oxia-etcd ./cmd`, and pass
  `oxia_etcd_binary`. Build Oxia the same way, with `-tags disable_trap`; set `GOARCH` to the one of the machines.
- **Losing the machine of the serving gateway**: the standby takes over in 10 to 40 seconds, but the API servers write
  again only after about two minutes. Their etcd client backs off from the standby while its port is closed, and waits
  for the lost machine to time out.
- **kubeadm** skips its `ExternalEtcdVersion` preflight check: it gets `/version` over HTTP on the etcd port, which
  the gateways serve over gRPC only.
- **The control plane endpoint** of kubeadm is the first control plane. Put a load balancer in front of the control
  planes, and set `kubernetes_control_plane_endpoint` to it, so that the cluster doesn't depend on that machine.
- Without workers, the pods run on the control planes.
