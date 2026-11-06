# kubernetes Questions — Checkpoint 5 (2026-11-06)

_Extracted from conversation since: 2026-11-05_

_**Try:** lines are the agent's suggestions. They weren't run unless marked otherwise._

---

## client-go Transport & Auth

- @kubernetes/_upstream/staging/src/k8s.io/client-go/transport/config.go#L37-41 what are tehse strings? what are they called? what purpose do they have?
- @kubernetes/_upstream/staging/src/k8s.io/client-go/rest/transport.go#L122-123 -- what's an exec provider?
- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/apiserver.go#L164-164 -- why is there a need for a client? also, crdClient only covers the client side config (e.g. it holds the address of the apiserver itself), or does it only hold the address of the recipient?
- crdClient: where is the recipient's address stored at?
  - **Try:** break at `client-go/rest/request.go:565` and inspect `r.c.base` on a loopback request.
- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L142-142 -- where can I find the address of the client and the address of the server (recipient address)?; who is actually the client? and who is the recipient?
  - **Try:** break at `handler.go:188` and compare `r.RemoteAddr` for a loopback request with one from `kubectl`.
- @kubernetes/_upstream/pkg/controlplane/instance.go#L321-330 -- line 330 creates a client. but line 321 (in the fn that it invokes) also creates a client. are they different? it seems they are created just the same.

## Informers & Cacher

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/client/informers/externalversions/apiextensions/v1/customresourcedefinition.go#L58-58 -- what is the difference between informers and the cacher (@kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/registry/customresourcedefinition/etcd.go#L42-42) ?
- if the informer watches apiserver, then becayse aouserver watches etcd, it means taht the informer indirectly watches etcd?A
- >In-process Lister reads and event handlers
  what does it mean?
- @kubernetes/_upstream/pkg/controlplane/controller/clusterauthenticationtrust/cluster_authentication_trust_controller.go#L98-98 -- will this create a scoped informer?

## CRD Establishing

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/controller/establish/establishing_controller.go#L54-54 -- what is the purpose of this?
- >  - Why it's separate: with several apiservers, it delays establishing by 5 seconds so the others can catch up (customresource_handler.go:487-495). The code's own TODO calls
      this an arbitrary wait.
  does not make any sense. explain better.

## CRD Handler Storage & Concurrency

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/customresource_handler.go#L214-214 -- why thuis? and why storing a struct atomically? isnt this costly?
- >plus double-checked locking for lazy creation
  explain more about this.
  - **Try:** set one breakpoint at `customresource_handler.go:619` and another at `:1065`. Create a CRD and send two requests: the first should hit `:1065` and the second `:619`.
- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/customresource_handler.go#L617-633 -- still not clear
  - **Try:** set a breakpoint at `:633`, then send two requests at once to a CRD with no storage yet (restart the apiserver first if it's already been used). With the debugger's "suspend this goroutine only" option, the second request should find the entry at `:634`.
- why cant we take the registry a single time, during the lock? wouldnt we end with the same thing?
- so, atomic.Value ensures safety because it uses copy-on-write under the hood?
- still dont get it what 'safe swap of the refence' means.
  - **Try:** the race detector catches the plain-variable version. Write a small program with one goroutine assigning a new map to a plain global in a loop and another reading from it, then run `go run -race main.go`. Switch to `atomic.Value` and the warning goes away.
- your table isnt clear at all (write core vs reader core)
- but why woudl the compiler reoreder that instruction, such that step 3 appears before step 1 in compiled language? or, you meant the execution order done by the CPU, while the instructions scoped to a single CPU core remain the same?

## Go Language

- @kubernetes/_upstream/staging/src/k8s.io/client-go/tools/cache/shared_informer.go#L801-801 -- is this possible? to have a map whose keys are pointers? it means the pointer neeeds to have a String() method, correct?
  - **Try:** the `a`/`b` snippet runs as is in a small `main.go`. Add `m2 := map[[]int]bool{}` and the compiler rejects it with `invalid map key type []int`.

## Handler Chain & Routing

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/apiserver.go#L206-208 -- confused about this. CRD api groups re registred eg at /apis/customresourcedefinitions in the restful container. and now, the same prefix, /apis, is added to the non-restful container. how does the director differentiate between them? i notice that the only handler of the non-restful container is the crdHandler, which is also given the controller. what is the crtdHandler? what purpose does it have?
  - **Try:** compare the two routes: `kubectl get --raw /apis/apiextensions.k8s.io/v1`, then the same for a CRD's group/version.
  - **Try:** run the apiserver with `-v=5` and look for `satisfied by gorestful` vs `satisfied by nonGoRestful`.
  - **Try:** set a breakpoint at `customresource_handler.go:617`, then create a CRD and send it two requests. Only the first should get past the fast path.
- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/apiserver.go#L206-206 -- is this handler scoped to the apiextensions-apiserver?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/handler.go#L187-189 -- when is this invoked?

## Control Plane Server Setup

- ```
     [0] string = "kube-system"
     [1] string = "kube-public"
     [2] string = "default"
     [3] string = "kube-node-lease"
  ```
  -- tell me about these system namespaces
  - **Try:** `kubectl -n kube-node-lease get lease`.
- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L197-197 what is it and what problem does it solve?
- what is the 'kubernetes' service?
  - **Try:** `kubectl get svc,endpointslice -n default -l kubernetes.io/service-name=kubernetes`.

## ServiceAccount Tokens & OIDC

- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L105-105 -- what is it meant by metadata provider? what kind of provider? what kind of metadata?
- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L130-130 -- what is the purpose of this?
- @kubernetes/_upstream/pkg/routes/openidmetadata.go#L65-72 -- dont these have a handler?
- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L130-130 -- so, it is not an OIDC server, it is an OIDC metadata server? why is this metadata so useful?
  - **Try:** `kubectl get --raw /.well-known/openid-configuration`, then `kubectl get --raw /openid/v1/jwks`.
- ```
  ▾ o.ServiceAccounts.KeyFiles []string = []string len: 1, cap: 1, ["/tmp/local-up-cluster.sh.4IhGGb/kube-serviceaccount.key"]
     [0] string = "/tmp/local-up-cluster.sh.4IhGGb/kube-serviceaccount.key"
  ```
  what is this?
- elaborate on the flow mentioned at 5. is this part of the OIDC protocol? Or OAuth2.0? which one?
- so, a pod ends the that token to AWS. where is ServiceAccount token obtained from? what is AWS in this case, an identity provider? what is the relation between AWS and apisever?
- what exactly are serivce acocunt tokens?
  - **Try:** `kubectl create token default | cut -d. -f2 | base64 -d 2>/dev/null` (the claims part isn't padded, so `base64` may complain, but it prints the JSON).
- if not using AWS STS, what are the altenratives? can I self host this? are there open source alternatives?
- also, regarding 1, tell me why is that needed? I dont undertand that purpoes of that flow.
- regarding 2, again, why would I need AWS (and kubectl create token <sa>) ? what problem am I solving?

## Aggregation & Cluster Authentication Trust

- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L236-236 -- what does cluster authentication refer to? authentication between components of the cluster, like between kubelet and apiserver? or between multiple API servers?
  - **Try:** `kubectl -n kube-system get cm extension-apiserver-authentication -o yaml`.
- @kubernetes/_upstream/pkg/controlplane/apiserver/server.go#L237-237 -- why does it have 'trust' in name?
- what is an aggregated API?
  - **Try:** `kubectl get apiservices` lists the local entries and any aggregated ones.
