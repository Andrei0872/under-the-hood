# Lima VM

```bash
limactl start --name=k8s-dev k8s-dev.yaml   # create + provision the VM
limactl shell k8s-dev                        # open a shell inside it
```

## Updating an existing VM

Lima runs the VM from its own copy of the config (`~/.lima/k8s-dev/lima.yaml`), not from this file. After editing `k8s-dev.yaml`:

```bash
cp k8s-dev.yaml ~/.lima/k8s-dev/lima.yaml
limactl validate ~/.lima/k8s-dev/lima.yaml
limactl stop k8s-dev && limactl start k8s-dev
```

The restart is needed because provision scripts (and settings like `cpus`/`memory`) are only applied at boot. Provision runs on every boot, so its steps must be safe to re-run.
