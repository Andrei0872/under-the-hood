# WIP: Debugging a Local K8s Cluster

![Diagram](_assets/debugging-a-local-k8s-cluster.png)

[![Watch on YouTube](https://img.shields.io/badge/Watch_on-YouTube-red?logo=youtube&style=for-the-badge)]({{VIDEO_URL}})

Other Kubernetes write-ups in this repo assume you can pause a running cluster and step through its code. This one shows how to set that up: a single-node cluster started by `hack/local-up-cluster.sh`, with dlv attached to one of its components and Neovim attached to dlv.

## Table of Contents

* [Prerequisites](#prerequisites)
* [Debug Client Configuration](#debug-client-configuration)
* [Debugging in Action](#debugging-in-action)

## Prerequisites

* **Linux.** The kubelet only runs on Linux. On macOS, set up the VM first: see [`_lima/readme.md`](_lima/readme.md). It comes with Go, dlv, containerd and Neovim.

* **This repo, with the Kubernetes submodule** (pinned to `v1.34.0`, shallow), and **etcd**, which the cluster uses as its store. In the VM, run these from `limactl shell k8s-dev`, which forwards your SSH key for the clone:

  ```bash
  git clone git@github.com:Andrei0872/under-the-hood.git ~/src/under-the-hood
  cd ~/src/under-the-hood && git submodule update --init --depth 1 --filter=blob:none --single-branch kubernetes/_upstream
  cd kubernetes/_upstream && hack/install-etcd.sh
  ```

  The forwarded key comes from the Mac's ssh-agent, so the key must be loaded there (`ssh-add -l` lists it). If the clone fails with `Permission denied (publickey)`, run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` on the Mac. To have it loaded automatically, add this to the Mac's `~/.ssh/config`:

  ```
  Host *
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519
  ```

* **[dlv](https://github.com/go-delve/delve)** and **Neovim with [nvim-dap](https://github.com/mfussenegger/nvim-dap)** (my setup is in [my dotfiles](https://github.com/Andrei0872/dotfiles/blob/master/nvim/lua/plugins/dap.lua)).

## Debug Client Configuration

Same as for etcd: an adapter that points Neovim at an already running dlv server, and an **Attach to debug server** configuration that asks for the port. See [etcd's Debug Client Configuration](../etcd/debugging-a-local-cluster.md#debug-client-configuration).

## Debugging in Action

All commands run from `kubernetes/_upstream`.

1. **Build the components with debug info** (`DBG=1` disables optimizations and inlining):

   ```bash
   make DBG=1 WHAT="cmd/kubectl cmd/kubelet cmd/kube-apiserver cmd/kube-scheduler cmd/kube-controller-manager cmd/kube-proxy"
   ```

2. **Start the cluster from those binaries.** `-O` skips the script's own, non-debug, rebuild:

   ```bash
   hack/local-up-cluster.sh -O
   ```

3. **Attach dlv to a component**, here the apiserver. Ubuntu only lets you attach to your own child processes (`kernel.yama.ptrace_scope=1`), so dlv runs as root. `--only-same-user=false` then lets Neovim, running as you, connect to it:

   ```bash
   sudo ~/go/bin/dlv attach $(pgrep -x kube-apiserver) --headless --listen=127.0.0.1:2345 \
     --api-version=2 --accept-multiclient --continue --only-same-user=false
   ```

   The same command works for every component, including the kubelet and kube-proxy, which run as root. `-x` matches the exact process name, which skips the `sudo` wrapper processes; the kernel cuts names to 15 characters, so the controller-manager is `pgrep -x kube-controller`.

4. **Connect Neovim to dlv:**
    1. Run `:DapContinue`.
    2. Choose the **Attach to debug server** configuration.
    3. Enter port `2345`.

5. **Add a breakpoint and hit it.** Every LIST request reaches the storage in `ListResource`: [`get.go#L302`](https://github.com/kubernetes/kubernetes/blob/f28b4c9efbca5c5c0af716d9f2d5702667ee8a45/staging/src/k8s.io/apiserver/pkg/endpoints/handlers/get.go#L302). Controllers list too, so make it conditional on `scope.Resource.Resource == "nodes"`, then:

   ```bash
   cluster/kubectl.sh get nodes
   ```
