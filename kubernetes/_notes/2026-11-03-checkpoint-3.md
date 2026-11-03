# kubernetes Questions — Checkpoint 3 (2026-11-03)

_Extracted from conversation since: 2026-11-03_

_**Try:** lines are the agent's suggestions. They weren't run unless marked otherwise._

---

## Scheme & runtime.Object

- why gvkToType and typeToGVK have different number of times? arent there supposed to be reversed between each other? (debugger dump shortened to its key lines):
  ```
  ▾ gvkToType map[k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind]reflect.Type = map[schema.GroupVersionKind]reflect.Type [...]
     len() int = 36
   ▸ [key 0] k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = schema.GroupVersionKind {Group: "apiextensions.k8s.io", Version: "v1beta1", Kind: "GetOptions"}
   ▾ [key 31] k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = schema.GroupVersionKind {Group: "apiextensions.k8s.io", Version: "v1beta1", Kind: "WatchEvent"}
      Group string = "apiextensions.k8s.io"
      Version string = "v1beta1"
      Kind string = "WatchEvent"
  ▾ typeToGVK map[reflect.Type][]k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = map[reflect.Type][]schema.GroupVersionKind [...]
     len() int = 21
   ▾ [val 0] []k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = []schema.GroupVersionKind len: 1, cap: 1, [(*"schema.GroupVersionKind")(0x400084cb10)]
    ▾ [0] k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = schema.GroupVersionKind {Group: "apiextensions.k8s.io", Version: "v1beta1", Kind: "CustomResourceDefinitionList"}
   ▸ [val 5] []k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = []schema.GroupVersionKind len: 3, cap: 4, [(*"schema.GroupVersionKind")(0x400052efc0),(*"schema.GroupVersionKind")(0x400052eff0),(*"schema.GroupVersionKind")(0x400052f020)]
  ```
- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/types.go#L375-377 -- is this how the object (e.g. CustomResourceDefinition) ends implementing the runtime.object interface?

## Watch Cache Configuration

- what are these strings? do they indicate watch cache names?:
  ```
  ▾ f.Options.WatchCacheSizes []string = []string len: 2, cap: 2, ["events#0","events.events.k8s.io#0"]
     [0] string = "events#0"
     [1] string = "events.events.k8s.io#0"
  ```

## Generic Registry Store

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/registry/generic/registry/store.go#L1550-1553 -- when are Indexers already defined?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/registry/generic/registry/store.go#L1579-1584 -- how do these differ?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/registry/generic/registry/store.go#L1603-1603 -- what is the purpose of this?
- what does it mean to delete a whole collection? collection of what? when?
  - **Try:** In a throwaway namespace: `kubectl delete --raw "/api/v1/namespaces/demo/configmaps?labelSelector=app=x"` runs a real collection delete. Compare with `kubectl delete cm -n demo -l app=x -v=6`, which should show one `DELETE` per object.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/registry/generic/registry/store.go#L1638-1638 -- how does it differ from the latency tracker and the db monitoring stats obtained periodically from etcd?
  - **Try:** `kubectl get --raw /metrics | grep -E "apiserver_storage_objects|storage_consistency_checks"`

## etcd Client, Compaction & Monitoring

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go#L427-427 -- what is the purpose of this? is this the place where etcd compaction is controlled from the apiserver? compaction refers to the revisions of the same resource (e.g. customresourcedefition/1, */2, */3).
- @kubernetes/_upstream/vendor/go.etcd.io/etcd/client/v3/kubernetes/client.go#L36-36 -- why a self reference?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go#L489-489 -- could there be more instances of etcd?
- what are some real uses cases that call for multiple etcd endpoints?
  - **Try:** `kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep etcd-servers`
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go#L496-496 -- what does it do? why not a simple interval? what does jitter actually mean?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go#L438-441 -- there are tracking two diffenert thigns: one concerns network laterncy (latency tracker) and the other concenrs the actual database stats that are given by etcd itself. is this correct?
  - **Try:** `kubectl get --raw /metrics | grep etcd_db_total_size`

## Storage Transformers & Corrupt Objects

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/value/transformer.go#L59-62 -- is this called interface union or something like, in Go?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go#L454-454 -- what's this about? when and WHY can such corrupted objects occur?

## CRD Storage & Status

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/apiserver.go#L153-154 -- so, two different etcd clients (which implies, on apiserver side at least, extra lease managers, compactors and other monitoring work), one fore customresourcedefinitions and one set for customresourcedefinitions/status? what does '/status' actually store?
  - **Try:** `etcdctl get /registry/apiextensions.k8s.io/customresourcedefinitions --prefix --keys-only`

## Cacher & Watch Cache

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L444-444 -- what is the purpose of this? provide a real use case.
- not clear what the cache compactor does.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/progress/watch_progress.go#L45-45 -- why using this over channels?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L374-374 -- what is the purpose of a real clock in a cache? TTL for eviction?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L66-71 -- what epsilon?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L425-425 -- wht's this?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/store.go#L127-129 -- are indexers just like database indexes?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/store_btree.go#L35-35 -- what does the degree reprsent?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/store_btree.go#L29-29 -- wouldnt a b+tree be more efficient for list operations?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/watch_cache.go#L199-199 -- what is a snapshotter? why snapshots? what problems do they solve? isnt a cacher already a snapshotter? what value does a snapshotter providers on top of the cacher?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L432-432 -- is the reflector the one responsible for keeping the cache up to date with the server? it seems it does it via some or of polling. am i correct?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L445-445 -- so, a snpahosts from cache also require a compactor. is snpshot something like materialized views in databases?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/cacher.go#L886-886 -- what is this event for?
  - **Try:** See bookmarks arrive: `kubectl get --raw "/api/v1/namespaces/default/configmaps?watch=1&allowWatchBookmarks=true"`. They should appear about once a minute.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/progress/watch_progress.go#L68-68 -- what is the purpose of a conditional progress rqeuester?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/storage/cacher/delegator.go#L68-68 -- why is it needed? what can go bad in terms of cache consistency?
- what do you mean by 'page'? give a concrete & simple example. also, I did not understand that you meant.
  - **Try:** `kubectl get --raw "/api/v1/pods?limit=2"` shows `metadata.continue` and `metadata.resourceVersion` in the response, if you have more than 2 pods. Pass the token back with `&continue=<token>` to get page 2.
- ok, so k8s also implements MVCC at its apiserver-level, besides etcd's mvcc? isnt this redundnat or even costly?

## Large Lists & Cluster Scale

- why does it come to large lists? is it common? what kind of activity generates large lists?
  - **Try:** `kubectl get pods -A -v=6 --chunk-size=2`
- 5000-node cluster = 5000 VMs?
  - **Try:** `kubectl get nodes -o wide`
