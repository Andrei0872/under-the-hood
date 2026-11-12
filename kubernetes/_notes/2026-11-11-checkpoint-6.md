# kubernetes Questions — Checkpoint 6 (2026-11-11)

_Extracted from conversation since: 2026-11-06_

---

## Control plane: storage providers & API groups

- @kubernetes/_upstream/pkg/controlplane/instance.go#L387-387 -- this is a provider of what? what does it provide?
- @kubernetes/_upstream/pkg/controlplane/instance.go#L411-435 -- what is a provider? provider vs API Group?
- @kubernetes/_upstream/pkg/controlplane/apiserver/apis.go#L98-98 -- what is a resourceExpirationEvaluator? why can a resource expire? what does it mean to expire?

## Services: IP & port allocation

- @kubernetes/_upstream/pkg/registry/core/service/portallocator/controller/repair.go#L54-56 -- what kind of leaks? why can they occur?
- @kubernetes/_upstream/pkg/features/kube_features.go#L602-603 -- what does it do? give a concrete example.
  - **Try:** `kubectl get servicecidrs,ipaddresses` (the resources are empty or missing if the gate is off).
- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L139-139 -- so, there is one serviceIPAllocator and one portallocator? how do these fit together?

## Core group storage (storage_core.go)

- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L157-157 -- what is this api group, policy? and what is this client for?
- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L162-162 -- podtemplate vs pods? is a pod template just a blueprint for a pod, while a pod is the actual instance for that blueprint? much like a class vs an object (an instance of the class)?
  - **Try:** `kubectl get podtemplates -A` (likely empty).
- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L253-255 -- podTemplates vs pods?
- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L218-219 -- so, the old serviceaccountstorage did not support pods?

## Bindings

- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L249-251 -- does this refer to RBAC?
- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L249-251 -- do bindings refers only to pods? or, only pods do define bindings? IOW, do bindings apply only to pods?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/groupversion.go#L122-122 -- why isnt bindings part of aggregatedDiscoveryResources?
  - **Try:** `kubectl api-resources | grep -w bindings` shows it with verb `create`.

## API types: kinds & resources

- @kubernetes/_upstream/pkg/apis/core/types.go#L6261-6262 -- this means that a kind is a materialized version of a resourcGe? ie, from resoureces kinds are created.
- @kubernetes/_upstream/pkg/registry/core/pod/storage/storage.go#L161-163 -- where is this added to the object kinds map? eg. here: @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L263-263.

## API installer & handlers

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L996-998 -- why are these provided here?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L466-467 -- what is the diff between these 2? give concrete examples.
  - **Try:** `kubectl get --raw /api/v1/nodes/<node>/proxy/healthz`
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L474-475 -- give an example of a storage that implements kind provider.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/storage_readiness_hook.go#L48-57 -- why a lock? this can be called from multiple goroutines?

## Managed fields (Server-Side Apply)

- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/util/managedfields/fieldmanager.go#L34-36 -- what kind of fields it is referring to? what are these fields?
  - **Try:** `kubectl get deploy -n kube-system coredns -o yaml --show-managed-fields`

## Go runtime / reflect

- @/usr/local/go/src/reflect/type.go#L191-196 -- if it is a struct field, how come is it possbile that it cannot be found?
