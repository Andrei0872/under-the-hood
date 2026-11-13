# kubernetes Questions — Checkpoint 8 (2026-11-13)

_Extracted from conversation since: 2026-11-12_

---

## Aggregator: APIService registration & discovery

- @kubernetes/_upstream/pkg/controlplane/apiserver/aggregator.go#L310-310 -- if curr == /api, does it mean this endpoint is responsible for aggregation discovery? and '/apis' as well?
  - **Try:** `kubectl get apiservice v1. -o yaml`
- @kubernetes/_upstream/pkg/controlplane/apiserver/aggregator.go#L140-140 -- apiservices == all of the API groups of the kube-apiserver (control plane) ?
- @kubernetes/_upstream/pkg/controlplane/apiserver/aggregator.go#L167-167 -- what does this atually mean? discovery? source of discovery?
- @kubernetes/_upstream/pkg/controlplane/apiserver/aggregator.go#L183-189 -- why is the healthcheck of all API services the responsibility of the aggregator server? is it because the aggregator is the first item in the server chain?

## OpenAPI

- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L455-462 openApi vs openApiv3?
  - **Try:** `kubectl get --raw /openapi/v3`
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L472-472 -- why is this done after calling PrepareRun() on the other parts of the server chain?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L443-443 -- will routes from the nonrestfulcontainer be listed/documented in the openapi route?
- openapi: v2 vs v3? @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/routes/openapi.go#L40-53

## Health checks (healthz / livez / readyz / statusz)

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L452-453 -- why are these created only for the nonrestfulcontainer? what about the restful container?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L463-465 -- so, besides livez, healthz, readyz, there is also statusz? what is this?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L198-200 -- how are these called, exactly? healthchecks, signals?
  - **Try:** `kubectl get --raw '/readyz?verbose'`
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L452-452 -- these healtchecks are scoped for each of API server part (one for aggregator, kube-apiserver, apiextensions-server). will they be gathered somehow so that a general health status can be reported per the 'broad' apiserver component?

## Server run & graceful shutdown

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L492-492 -- why is there a shutdown delay? for graceful shutdown?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L492-497 -- the way I read this: delay must pass AND preshutdown hooks must be invoked AND return healthly, AND ONLY THEN NotAcceptingRequests is signaled.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L530-530 -- uds profiling?? local profiling agent?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L542-544 -- so, if there N signals, channel at iteration i won't be consumed (ie <-channel:) UNTIL channel at iteration i-1 has been consumed.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L542-542 -- is this perhaps a healthz check for all the 3 api servers ?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L587-587 -- why WithoutCancel(ctx); if the passed stopCh sends, will withoutcancel lead to the server not being stopped?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L772-773 -- why this?
- re 13: how does the LB notices that one of its routing servers have stepped into the graceful shutdown phase?
  - **Try:**
    ```
    watch -n0.5 'kubectl get --raw "/readyz?verbose" | grep shutdown'
    kubectl get endpointslices -l kubernetes.io/service-name=kubernetes -w
    ```
    then restart the kube-apiserver static pod (move its manifest out of `/etc/kubernetes/manifests` and back).

## In-process API clients vs direct storage

- the reason removing an endpoint is an api call is because it's being done through the client interface, which goes through the entire request pipeline? but why, though? why not directly call the etcd client? is it because it needs to go through all filters, like authentication and so on? but why, though, since its the very same process, it does not not need authn or authz.
  - **Try:** `etcdctl get /registry/masterleases/ --prefix --keys-only` against `/registry/services/endpoints/default/kubernetes`; only the second is visible through `kubectl get --raw /api/v1/namespaces/default/endpoints/kubernetes`.
