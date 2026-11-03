# Service IP allocation & hands-on "Try" list

## 1. Service IP allocation: one bitmap per range → one object per IP

**Old design.** The whole Service ClusterIP range is a single etcd key, `/registry/ranges/serviceips`. Its value is a `RangeAllocation` object holding a bitmap (one bit per IP; 1 = taken). NodePorts work the same way under `/registry/ranges/servicenodeports`.

Allocating an IP is a read-modify-write of that one key, guarded by CAS on its `resourceVersion` (`pkg/registry/core/service/allocator/storage/storage.go:155-173`):

1. Read the bitmap (rv=100).
2. Set a free bit (`bitmap.go:100`, O(1) in memory).
3. Write the **whole** bitmap back, only if rv is still 100.

Problems:

- **Hot key / contention.** The CAS guards the whole key, so two allocations of *different* IPs still conflict. Every Service creation in the cluster competes for one key and retries on conflict.
- **O(range size) per write.** etcd has no partial updates, so flipping one bit rewrites the whole value (`Snapshot()` → `big.Int.Bytes()`, `bitmap.go:184`). A `/16` range is about 8 KiB per write, and a `/12` up to about 128 KiB.
- **Write amplification.** That full value is replicated via Raft, written to every member's WAL, and kept as a new MVCC revision until compaction.

**New design** (feature gate `MultiCIDRServiceAllocator`, `pkg/registry/core/rest/storage_core.go:337`). Each allocated IP is its own API object, `IPAddress` (`networking.k8s.io`), named after the IP: `/registry/ipaddresses/10.96.0.5`. The ranges themselves are `ServiceCIDR` objects. Allocating means *create-if-not-exists* (`pkg/registry/core/service/ipallocator/ipallocator.go:154`):

- Different IPs mean different keys, so there is **no conflict**. Only callers racing for the *same* IP collide; the loser gets `AlreadyExists` and picks another IP.
- Each write is small and constant-size, independent of the range size.
- Allocations are visible and debuggable: `kubectl get ipaddresses`.
- Ranges become API objects, so they can be added or changed at runtime.

**Why it's clever:** it's a **lock-granularity** change. The CAS moves from "the whole range" (coarse) to "one IP" (fine), and the storage layer's own "create fails if the key exists" does the uniqueness work. The general lesson: *a structure that's cheap in memory (a bitmap) can be expensive in a store that only supports whole-value writes. With a KV store, choose key granularity to match the unit of contention.*

**Trade-off:** many more objects (one etcd key per Service IP), and a repair/reconcile loop is still needed to clean up leaked `IPAddress` objects.

## 2. "Try" list

Paths are relative to `_upstream/`. The k8s.io library paths are under `staging/src/k8s.io/`.

### apiserver internals
- **Debug socket** (pprof over a Unix socket, no authn/authz): `curl --unix-socket <--debug-socket-path> http://x/debug/pprof/`
- **APF** (API Priority and Fairness) state: `kubectl get --raw /debug/api_priority_and_fairness/dump_priority_levels`, and see its config with `kubectl get flowschemas,prioritylevelconfigurations`
- **Health checks**: `kubectl get --raw '/readyz?verbose'` lists every check; `kubectl get --raw /readyz/shutdown` runs one check
- **Registered verbs per resource**: `kubectl get --raw /openapi/v2 | jq '.paths["/api/v1/namespaces/{namespace}/pods/{name}"] | keys'`. Compare with `.../pods/{name}/log` (get only) and `.../pods/{name}/exec` (CONNECT shows as get/post)

### Aggregation, APIServices, metrics APIs
- **List APIServices**: `kubectl get apiservices`. `Local` = served in-process; anything else is an aggregated server. `kubectl get apiservices | grep -v Local` shows only aggregated ones
- **Who implements metrics.k8s.io**: `kubectl get apiservice v1beta1.metrics.k8s.io -o yaml` (see `spec.service`)
- **Raw metrics API** (what `kubectl top` uses): `kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | jq '.items[0]'`. Compare with `staging/src/k8s.io/metrics/pkg/apis/metrics/v1beta1/types.go`. Without metrics-server you get 404/503
- **Pod CPU/memory usage** (CPU in nanocores): `kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/default/pods" | jq '.items[].containers[].usage'`
- **Custom metric names an adapter offers**: `kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq '.resources[].name'`
- **HPA without metrics-server**:
  1. `kubectl autoscale deploy <x> --cpu-percent=50 --min=2 --max=5`
  2. `kubectl describe hpa <x>`: look for `ScalingActive False FailedGetResourceMetric`
  3. `kubectl scale deploy <x> --replicas=1`: the HPA restores 2 (min is enforced without metrics)
- **sample-apiserver** (reference aggregated server, `staging/src/k8s.io/sample-apiserver/`): deploy it, run `kubectl get --raw /apis/wardle.example.com/v1alpha1`, and break in `staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_proxy.go` to watch the proxy hop

### CRDs / apiextensions
- **CRDs and their status**: `kubectl get crd`, then `kubectl get crd <name> -o jsonpath='{.status.conditions}' | jq` (NamesAccepted, Established)
- **The apiextensions group is tiny**: `kubectl get --raw /apis/apiextensions.k8s.io/v1 | jq '.resources[].name'`

### etcd
- **CRDs are stored in etcd**: `etcdctl get /registry/apiextensions.k8s.io --prefix --keys-only`. An aggregated group like `metrics.k8s.io` has no keys there
- **resourceVersion = etcd revision**: run `kubectl get cm -A -o jsonpath='{.metadata.resourceVersion}'` before and after `kubectl create cm x`; it increases
- **See apiserver → etcd writes live**: `etcdctl watch --prefix /registry`, then `kubectl create cm x` in another shell (values are protobuf; use `-w json` or pipe to `strings`)
- **etcd call metrics** per operation and resource: `kubectl get --raw /metrics | grep etcd_request_duration_seconds_count`
- **etcd call traces**: enable apiserver tracing (`--tracing-config-file`) and export to Jaeger. `staging/src/k8s.io/apiserver/pkg/storage/etcd3/store.go:264-321` already emits the spans
- **Log every etcd gRPC call** (as a `_patches/` patch): add `grpc.WithChainUnaryInterceptor(logFn)` next to the existing interceptors at `staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go:316`
- **Service IP bitmap** (old allocator): `etcdctl get /registry/ranges/serviceips --print-value-only | strings`

### Breakpoints (storage wiring)
- **All etcd reads/writes**: `staging/src/k8s.io/apiserver/pkg/storage/etcd3/store.go`, in `Get`, `GetList`, `Create`, `GuaranteedUpdate`
- **One etcd store per resource**: `staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go:426` (`newETCD3Storage`). Inspect `c.GroupResource` on each hit, then create a CRD and see it hit again at runtime
- **Pod storage construction**: `pkg/registry/core/pod/storage/storage.go:97`
- **Request path**: `staging/src/k8s.io/apiserver/pkg/registry/generic/registry/store.go:853`, while running `kubectl get pod <x>`. Expand `e.Storage.Storage` to see `Cacher → etcd3.store`
- **Handler wiring**: `staging/src/k8s.io/apiserver/pkg/endpoints/installer.go:803` with condition `resource == "pods"`. Inspect `getter`'s concrete type, then step into `handlers.GetResource`

### Controllers & coordination
- **Level-triggered controller shape**: in `pkg/controller/replicaset/replica_set.go`, compare the event handlers (`addPod`, `deletePod`, which only enqueue a key) with `syncReplicaSet` (lists pods and computes the difference)
- **Leader-election leases** (a real distributed lock): `kubectl -n kube-system get lease`, then `kubectl -n kube-system get lease kube-scheduler -o yaml` and watch `holderIdentity` and `renewTime`

### Networking
- **The `kubernetes` Service**:
  - `kubectl get svc kubernetes` shows the ClusterIP
  - `kubectl get endpointslices -l kubernetes.io/service-name=kubernetes` shows the real apiserver IPs
  - `kubectl run tmp --rm -it --image=busybox -- sh -c 'cat /etc/resolv.conf; nslookup kubernetes.default; env | grep KUBERNETES_'` shows DNS search domains and the injected env vars

### Go
- **Generated vs reflection deep copy benchmark**: generated code was ~3.6× faster with ~4× fewer allocations. The benchmark was a temporary file (gone with the session). Recreate it with a struct that has scalars + map + slice, a hand-written `DeepCopyInto`, and a recursive `reflect`-based copier. Run `go test -bench . -benchmem`, then add nested fields and watch the gap grow

### Health checks, identity, storage versions
- **Log health check** (fails if `klog.Flush()` hasn't completed in 2 min): `kubectl get --raw '/livez?verbose' | grep log`. Code: `staging/src/k8s.io/apiserver/pkg/server/healthz/healthz.go:78-91`
- **APIServer identity lease** (ID = sha256 over length-prefixed hostname + "kube-apiserver"): `kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver`

### Scheme & envelopes
- **`Status` envelope** (error body): `kubectl get --raw /api/v1/namespaces/default/pods/nope`
- **`WatchEvent` envelope** (one per stream line, `{"type":"ADDED","object":...}`): `kubectl get --raw '/api/v1/pods?watch=1' | head -c 300`
- **Hub-and-spoke conversion**: `grep -n '^func Convert_.*HorizontalPodAutoscaler_To' pkg/apis/autoscaling/v1/conversion.go pkg/apis/autoscaling/v2/conversion.go`. Only v1↔internal and v2↔internal exist, no v1↔v2
- **Decode → internal**: breakpoint at `staging/src/k8s.io/apimachinery/pkg/runtime/serializer/versioning/versioning.go:178` (`c.convertor.Convert(obj, into, ...)`) during a `kubectl create`

### Loopback client & TLS
- **SNI picks the loopback cert vs the serving cert**:
  - `openssl s_client -connect 127.0.0.1:6443 -servername apiserver-loopback-client </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -ext subjectAltName`: issuer `apiserver-loopback-client-ca@<ts>`, SAN `apiserver-loopback-client`
  - Same with `-servername localhost`: you get `/var/run/kubernetes/serving-kube-apiserver.crt` (issued by `server-ca`)
- **Loopback cert is regenerated on every start**: restart the apiserver and rerun the command above; the `@<unix-time>` in the CN/issuer changes
- **Loopback client = server-verified TLS + bearer token, no client cert**: breakpoint in `staging/src/k8s.io/client-go/transport/transport.go` (`TLSConfigFor`). `RootCAs` is set from `CAData` and `ServerName=apiserver-loopback-client`. No `GetClientCertificate`/`CertData`
- **Leaf is pinned (it's in RootCAs itself)**: Delve breakpoint at `crypto/x509.(*Certificate).Verify` with condition `opts.DNSName == "apiserver-loopback-client"`. Step over `verify.go:603`; `opts.Roots.contains(c)` returns `true`, so no chain building happens
- **Verify a cert signature by hand**:
  1. `openssl s_client -connect 127.0.0.1:6443 -servername apiserver-loopback-client -showcerts </dev/null 2>/dev/null`
  2. Save the two PEM blocks as `leaf.pem` and `ca.pem`
  3. `openssl x509 -in leaf.pem -noout -text | grep -A1 "Issuer\|Authority Key\|Signature Algorithm"`: the leaf references its parent by name + key ID only
  4. `openssl verify -CAfile ca.pem leaf.pem`
