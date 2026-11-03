# Experiment: tracing apiserver → etcd requests

**Goal:** see each API request as a tree of timed steps (a trace), down to the individual etcd calls, and link loopback requests back to the controller that made them.

## What's already in the code

- **Server spans.** The apiserver wraps every request in an OpenTelemetry span (one timed step of a trace). The storage layer adds child spans, e.g. `etcd3/store.go:264-321` (`Create etcd3` → `Encode` → `TransformToStorage` → `Txn call`), and `cacher.Get` / `cacher.GetList`, which carry the request's `audit-id` (`staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go:722-725`).
- **etcd client spans.** The etcd gRPC client is instrumented with `otelgrpc` (`staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go:321-328`), so every etcd call shows up as a child span with its method and duration, **even if etcd itself has tracing off**.
- **Loopback propagation.** In-process clients (the loopback ones) send a `traceparent` header (the W3C trace-context header that carries the trace ID across a connection). Their server-side span then joins the caller's trace, which answers "which controller made this request?" without a debugger.
- **Off by default.** With tracing disabled, `ctx` holds a `noop.Span` (seen in the debugger at `handlers/get.go:58`).

## Setup

### 1. Run an OTLP collector on `localhost:4317`

OTLP is the OpenTelemetry protocol; 4317 is its gRPC port. Jaeger all-in-one is a collector plus a UI:

```bash
# any container runtime works (docker, nerdctl, ...)
docker run --rm -d --name jaeger -p 16686:16686 -p 4317:4317 jaegertracing/all-in-one:1.62.0
# UI: http://localhost:16686 (forward the port from the lima VM if browsing from the Mac)
```

### 2. Write the apiserver tracing config

```yaml
# /tmp/apiserver-tracing.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: TracingConfiguration
endpoint: localhost:4317          # the default
samplingRatePerMillion: 1000000   # sample every request (fine locally, never in production)
```

Schema: `staging/src/k8s.io/component-base/tracing/api/v1/types.go:20`. The kind is registered in `staging/src/k8s.io/apiserver/pkg/apis/apiserver/v1/register.go:53`.

### 3. Pass `--tracing-config-file` to kube-apiserver

`hack/local-up-cluster.sh` has `ENABLE_TRACING=true` (`:110`), but it only configures the **kubelet** (`:935-940`). The apiserver command (`:666`) has no hook for extra flags. Options:

- **A patch in `_patches/`** (preferred): when `ENABLE_TRACING=true`, write the YAML above to `${TMP_DIR}` and add `--tracing-config-file=...` to the kube-apiserver command. This mirrors what the script already does for the kubelet.
- **A stand-in** (no upstream change): `_scripts/startup-debug.sh` already points `GO_OUT` at a directory of stand-ins. A kube-apiserver stand-in can `exec <real binary> "$@" --tracing-config-file=/tmp/apiserver-tracing.yaml`.

Then start the cluster with `ENABLE_TRACING=true` (this also traces the kubelet).

### 4. (Optional) etcd-side spans

To also see etcd internals, start etcd with its distributed-tracing flags pointing at `localhost:4317`. etcd here is 3.6.4 (`hack/lib/etcd.sh:19`), started without an extra-args hook (`hack/lib/etcd.sh:88`), so it needs a patch too. The flag names changed between etcd versions (`--experimental-enable-distributed-tracing` vs. non-experimental names), so check `etcd --help | grep -i tracing` first.

## Experiments

1. **`kubectl get nodes`.** In Jaeger, find the `kube-apiserver` service and the `GET /api/v1/nodes` trace. Expect: the APF filter, authz, `cacher.GetList` (with `audit-id`), and **one small etcd `Range` call**. That call is the consistent-read revision check (`GetCurrentResourceVersion`, `etcd3/store.go:686`, a limit-1 list), not the list itself, which is served from the watch cache.
2. **`kubectl get nodes --v=8 2>&1 | grep -i audit-id`.** Take the response's `Audit-Id` and find the same request in `/tmp/kube-apiserver-audit.log` (local-up-cluster logs every request at `Metadata` level, `hack/local-up-cluster.sh:649-672`) and in the trace (`audit-id` span attribute). One ID links all three views.
3. **Find who did the loopback `GET /api/v1/namespaces/kube-system`.** Open its trace. With `traceparent` propagated, the parent span belongs to the in-process client. Check whether it's the cluster-authentication-trust controller (`pkg/controlplane/controller/clusterauthenticationtrust/cluster_authentication_trust_controller.go:182`, repeats about every minute).
4. **Compare reads:**
   - `kubectl get --raw '/api/v1/nodes?resourceVersion=0'` → served from cache, **no** etcd span
   - `kubectl get --raw '/api/v1/nodes'` → cache plus the revision-check etcd span
   - `kubectl get --raw '/api/v1/nodes/<name>'` → a single GET without `resourceVersion` goes **straight to etcd** (`staging/src/k8s.io/apiserver/pkg/storage/cacher/delegator.go:145-150`)
5. **A write: `kubectl create cm x`.** Expect `Create etcd3` with its `Encode` / `TransformToStorage` / `Txn call` events. Compare its duration with the admission and validation spans.

## Gotchas

- Sampling 100% is noisy (controllers, leases, health checks). Filter in Jaeger by operation or tag.
- Spans that end within their threshold may be dropped from *logs* (`span.End(500ms)` logs only slow ones), but they're still exported to the collector.
- `kubectl` doesn't send `traceparent` itself, so its requests start new root traces on the server.
