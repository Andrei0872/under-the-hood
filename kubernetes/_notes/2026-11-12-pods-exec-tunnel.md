# `pods/exec`: a tunnel, not a stored subresource

**Idea:** `pods/status` reads or writes part of the Pod object in etcd. `pods/exec` touches neither the Pod nor etcd. The apiserver reads the Pod only to find its node, then **proxies a streaming connection** to that node's kubelet. The kubelet asks the container runtime to start the process. What changes is a running container, not an API object.

## Kinds of subresource

| Kind | Examples | What a request does |
|---|---|---|
| Stored view | `pods/status`, `*/scale` | Read or write part of the object in etcd |
| Action | `pods/eviction`, `pods/binding` | A create that triggers logic (checking a PDB, setting `nodeName`) |
| Connecter (tunnel) | `pods/exec`, `attach`, `portforward`, `log`, `proxy` | Opens a stream to the kubelet. Nothing is stored |

`ExecREST` implements `rest.Connecter`. It has no Getter or Updater, and `ConnectMethods()` returns `GET, POST` (`pkg/registry/core/pod/rest/subresources.go:88,200-202`). The installer turns those into one route per method (`staging/src/k8s.io/apiserver/pkg/endpoints/installer.go:1048-1073`).

## Concrete example: `kubectl exec nginx -- ls /`

Suppose a Pod `nginx` in namespace `default` runs on node `worker-1` (InternalIP `172.18.0.3`). The URLs below are reconstructed from the code. They are **not captured output**.

**1. kubectl → apiserver**

kubectl first tries WebSocket, which uses `GET` (`staging/src/k8s.io/kubectl/pkg/cmd/exec/exec.go:154`). If that fails it falls back to SPDY, which uses `POST` (`:158`).

```
GET /api/v1/namespaces/default/pods/nginx/exec?command=ls&command=%2F&container=nginx&stdout=true&stderr=true
Connection: Upgrade
Upgrade: websocket
Sec-WebSocket-Protocol: v5.channel.k8s.io
```

`v5.channel.k8s.io` is defined at `staging/src/k8s.io/apimachinery/pkg/util/remotecommand/constants.go:52`. The request passes the usual authentication, authorization (`create` on `pods/exec`) and admission.

**2. The apiserver finds the kubelet**

`ExecREST.Connect` (`pkg/registry/core/pod/rest/subresources.go:168`) calls `pod.ExecLocation` (`pkg/registry/core/pod/strategy.go:732`), then `streamLocation`:
- Reads the Pod and gets `spec.nodeName = worker-1` (`:763`).
- Looks up how to reach that node with `GetConnectionInfo`: address, port 10250, TLS (`:768`).
- Builds the URL with path `/<verb>/<ns>/<pod>/<container>` (`:779`):

```
https://172.18.0.3:10250/exec/default/nginx/nginx?command=ls&command=%2F&output=1&error=1
```

**3. apiserver ↔ kubelet**

`newThrottledUpgradeAwareProxyHandler` (`pkg/registry/core/pod/rest/subresources.go:253-256`) upgrades the connection and copies bytes in both directions, with bandwidth limiting. A WebSocket client is converted to SPDY toward the kubelet by the stream translator (`:178-188`). This hop uses the egress selector's "Cluster" context.

**4. kubelet → container runtime**

The kubelet's `/exec` route (`pkg/kubelet/server/server.go:514`) runs `getExec` (`:944`). That calls `GetExec` → CRI `Exec` (`pkg/kubelet/kuberuntime/kuberuntime_container.go:1290-1304`). containerd returns the URL of **its own streaming server**, and the kubelet proxies to it (`proxyStream`, `pkg/kubelet/server/server.go:964`). containerd then runs `ls /` inside the container's namespaces.

**5. Bytes on the wire**

Every frame is prefixed with a channel byte (`staging/src/k8s.io/apimachinery/pkg/util/remotecommand/constants.go:59-64`):

| Byte | Channel |
|---|---|
| 0 | stdin |
| 1 | stdout (the `ls` output) |
| 2 | stderr |
| 3 | error/status (exit code) |
| 4 | terminal resize |
| 255 | close a stream (v5) |

The result is **two proxies between two endpoints**, with one byte stream running through them:

```
you (terminal) ⇄ kubectl ⇄ apiserver ⇄ kubelet ⇄ containerd streaming server ⇄ `ls` process
                 client    proxy #1    proxy #2   server end (does the exec)
```

kubectl is the client end, because it owns your terminal's stdin and stdout. containerd's streaming server is the server end, because it starts the process and wires its stdio to the stream. Only the apiserver and the kubelet sit in the middle as `UpgradeAwareHandler` proxies (`pkg/registry/core/pod/rest/subresources.go:254`, `pkg/kubelet/server/server.go:912-915`). Nothing is written to etcd except, optionally, an audit log entry.

## Why the apiserver translates WebSocket to SPDY

- **What clients want.** SPDY is a dead protocol. Browsers, HTTP/2 stacks and many proxies and load balancers don't support it, but they all support WebSocket. So since 1.29/1.30, kubectl talks WebSocket to the apiserver (KEP-4006; gate `TranslateStreamCloseWebsocketRequests`, beta and on by default in 1.30, `pkg/features/kube_features.go:1816-1819`).
- **What WebSocket was missing.** Older WebSocket subprotocols (up to v4) had no way to close stdin while still reading stdout. `echo hi | kubectl exec -i pod -- cat` would hang. SPDY can close one stream on its own. **v5** added the `CLOSE` signal, channel 255 (`staging/src/k8s.io/apimachinery/pkg/util/remotecommand/constants.go:49-52,64`).
- **Who speaks v5.** Only the apiserver. The kubelet/CRI streaming server's WebSocket support stops at v4 (`staging/src/k8s.io/kubelet/pkg/cri/streaming/remotecommand/websocket.go:36-39`). SPDY is what every kubelet and runtime supports.
- **So the apiserver translates.** It accepts v5 WebSocket and opens SPDY toward the kubelet (`staging/src/k8s.io/apiserver/pkg/util/proxy/streamtranslator.go:36-37`). Other requests pass through unchanged (`translatingHandler`, `pkg/registry/core/pod/rest/subresources.go:189`). Doing this in one central place avoids changing every kubelet (which may be older than the apiserver) and every CRI runtime. **Pattern:** adapter / protocol translation at the gateway.

## Consequences

- **RBAC:** `create pods/exec` is effectively a shell inside the container. It is separate from `get pods` and much more powerful.
- **Network path:** the apiserver must be able to reach the kubelet on port 10250. That is why the `Cluster` egress type and Konnectivity exist.
- **Pattern:** API gateway / reverse proxy. The apiserver is the single authenticated entry point and forwards the stream to the right backend (the kubelet).

## Try

- `kubectl exec -v=8 nginx -- ls / 2>&1 | grep -E 'GET|POST|Upgrade|Protocol'` shows step 1.
- `kubectl get --raw /api/v1/nodes/<node>/proxy/healthz` reaches the same kubelet port through the apiserver, via `nodes/proxy`.
- Breakpoint at `pkg/registry/core/pod/strategy.go:779` to see the kubelet URL being built.
