# kube-apiserver graceful shutdown: how load balancers notice

**Question:** when an apiserver starts shutting down, how do the things routing traffic to it find out and stop sending requests?

**Short answer:** the apiserver never pushes anything to them. It fails readiness straight away, then keeps serving for a while so the routers can catch up:

- **External LB** (HAProxy, cloud NLB in front of the control-plane nodes): it polls `/readyz`. The `shutdown` readyz check starts failing as soon as shutdown begins.
- **In-cluster clients** (pods using `kubernetes.default`): a pre-shutdown hook removes this apiserver's IP from the `default/kubernetes` Endpoints. kube-proxy watches EndpointSlices and drops the IP from its rules.

## The shutdown sequence

Diagram: `staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go:478-520`, above `preparedGenericAPIServer.RunWithContext`.

| Step | Where | What happens |
|---|---|---|
| 1 | `genericapiserver.go:556` | `ctx` is cancelled, and `ShutdownInitiated` fires. From now on `/readyz` returns an error |
| 2 | `genericapiserver.go:561` | Sleep for `--shutdown-delay-duration`, then fire `AfterShutdownDelayDuration` |
| 2' | `genericapiserver.go:704-712` | In parallel, run the pre-shutdown hooks, then fire `PreShutdownHooksStopped`. It fires even if a hook returned an error, because the signal is sent from a `defer` |
| 3 | `genericapiserver.go:622-634` | Only when **both** 2 and 2' are done does `NotAcceptingNewRequest` fire |
| 4 | `genericapiserver.go:587-597` | The HTTP server is stopped. It runs on `context.WithoutCancel(ctx)`: it keeps ctx's values but not its cancellation, so cancelling `ctx` alone doesn't stop it. Without `--shutdown-send-retry-after` it stops on `NotAcceptingNewRequest`; with that flag it waits for in-flight requests to drain |

## Outside the cluster: external LB polls `/readyz`

- The readyz shutdown check is wired up in `PrepareRun`: `addReadyzShutdownCheck(ShutdownInitiated.Signaled())`, `genericapiserver.go:456-457`.
- The check itself is `NewShutdownHealthz` (`staging/src/k8s.io/apiserver/pkg/server/healthz/healthz.go:121-135`). It returns `"process is shutting down"` once the channel is closed.
- The LB's own health check sees `/readyz` returning non-200. After its failure threshold is reached, it takes the backend out of rotation.

Details that matter:

- The LB must probe **`/readyz`**. `/livez` and `/healthz` have no shutdown check and stay green during shutdown.
- `--shutdown-delay-duration` must be longer than the LB's probe interval × failure threshold. Otherwise the listener closes before the LB has noticed, and clients see connection errors.
- Clients that still arrive after the delay: with `--shutdown-send-retry-after` they get a 429 response with a `Retry-After` header, and HTTP/2 connections get a GOAWAY frame, which tells the client to reconnect (`staging/src/k8s.io/apiserver/pkg/server/options/server_run_options.go:75-78`).

## Inside the cluster: Endpoints removal for `kubernetes.default`

1. Pre-shutdown hook `stop-kubernetes-service-controller`: `pkg/controlplane/instance.go:363-366`.
2. `Controller.Stop` calls `EndpointReconciler.StopReconciling()`, then `RemoveEndpoints(...)`: `pkg/controlplane/controller/kubernetesservice/controller.go:113-130`.
3. The lease reconciler deletes this apiserver's master lease and rewrites the Endpoints and EndpointSlice without this server's IP: `pkg/controlplane/reconcilers/lease.go:329`.
4. kube-proxy sees the EndpointSlice change and removes the IP from its iptables/IPVS rules.

This is why `NotAcceptingNewRequest` waits for the pre-shutdown hooks (comment at `genericapiserver.go:630-632`). Removing the endpoint is itself an **API call** through the loopback client, so the server has to keep serving until the hook finishes.

### Why an API call and not a direct etcd write?

The same reconciler uses both paths:

- **Endpoints and EndpointSlices** go through a loopback clientset, a client that talks to this same apiserver (`pkg/controlplane/instance.go:224-226`).
- **Master leases** (`/masterleases/`) are written with a raw `storage.Interface` (`pkg/controlplane/reconcilers/lease.go:61-66`, built at `instance.go:229-233`).

The rule is whether the object is public API. Leases are private bookkeeping. Endpoints are watched by kube-proxy, read by users, and may be covered by admission policies. A public object has to go through the registry, which handles:

- encoding to the storage version
- encryption at rest
- the `/registry/...` key layout
- the strategy: defaulting, validation, `managedFields`
- admission
- audit
- resourceVersion conflicts

Authn/authz are not the reason, and they cost almost nothing here. The loopback token maps to the user `system:apiserver` in the group `system:masters` (`staging/src/k8s.io/apiserver/pkg/server/config.go:1183-1190`). That group is privileged and always authorized.

## Patterns

- **Readiness-gated drain:** fail readiness, keep serving while the routers converge, then close. Ordinary Pods work the same way: readiness controls Endpoints membership, and `preStop` plus `terminationGracePeriodSeconds` set the delay.
- **Everything talks through the API:** in-process controllers are API clients too, so the API is the only writer of public state. Private, internal-only state such as the master leases is the deliberate exception.

## Try

- Terminal 1: `watch -n0.5 'kubectl get --raw "/readyz?verbose" | grep shutdown'`
- Terminal 2: `kubectl get endpointslices -l kubernetes.io/service-name=kubernetes -w`
- Restart the kube-apiserver static pod (move its manifest out of `/etc/kubernetes/manifests` and back). Expect to see `[-]shutdown failed` briefly, and the endpoint disappearing.
