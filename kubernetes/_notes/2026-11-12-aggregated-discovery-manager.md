# Aggregated discovery manager (kube-aggregator)

**Idea:** a single `GET /apis` with `Accept: application/json;g=apidiscovery.k8s.io;v=v2;as=APIGroupDiscoveryList` returns **every** group, version and resource in the cluster. Built-in and CRD groups publish their entries directly. For **remote** APIServices (aggregated APIs behind a Service), the discovery manager fetches each backend's discovery, caches it, and merges it into that one document.

## Wiring

`staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go`, in `completedConfig.NewWithDelegate`:

| Line | What happens |
|---|---|
| `:278-279` | `/apis` serves either the merged (aggregated) document or the legacy group list, depending on the `Accept` header (`staging/src/k8s.io/apiserver/pkg/endpoints/discovery/aggregated/wrapper.go:67-77`) |
| `:364-368` | `NewDiscoveryManager(...WithSource(aggregated.AggregatorSource))`. Entries are tagged "aggregator" so they don't overwrite built-in or CRD entries for the same group-version |
| `:371-379` | Post-start hook: wait until the APIService registration controller has synced, then `Run` |
| `:524`, `:552` | `APIAggregator.AddAPIService` passes each APIService and its proxy handler to the manager |

## Remote only

```go
// staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_discovery.go:553-558
func (dm *discoveryManager) AddAPIService(apiService *apiregistrationv1.APIService, handler http.Handler) {
	// If service is nil then its information is contained by a local APIService
	// which is has already been added to the manager.
	if apiService.Spec.Service == nil {
		return
	}
```

Local APIServices (built-in groups and CRDs) never pass through here. Their servers write into the shared `AggregatedDiscoveryGroupManager` themselves, under their own sources.

## Fetching

`fetchFreshDiscoveryForService` (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_discovery.go:216`):

- **Cache per backend Service, not per group-version** (`serviceKey`, `:116-128`). A backend that serves several group-versions is fetched only once.
- **Freshness check:** if the cached entry is newer than the last time the APIService was marked dirty, it is reused (`:220-223`).
- **No real HTTP client.** It builds a fake `GET /apis` request and calls the **proxy handler in-process**, with a 5s `TimeoutHandler` (`:227-228`). The proxy handler then makes the actual network call to the backend, using the front-proxy client cert (see `2026-11-12-aggregator-front-proxy-client-cert.md`).
- **Identity:** the request runs as `system:kube-aggregator` in `system:masters` (`:236-238`).
- **Conditional request:** it sends `If-None-Match` with the cached ETag (`:245-246`), so an unchanged backend answers with a 304 and no body.
- **Fallback:** if the backend doesn't support aggregated discovery v2, it fetches legacy `/apis/<group>/<version>` and converts that (`:310-321`).

## Merging

`syncAPIService` (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_discovery.go:382`):
- It pulls this group-version out of the cached document and calls `AddGroupVersion` and `SetGroupVersionPriority` (`:433-434`). The priorities come from `spec.groupPriorityMinimum` and `spec.versionPriority`.
- **Failure handling:** if a fetch fails, it keeps the last cached copy and marks it `Freshness: Stale` (`:425-431`). With no cache at all, it publishes the group-version with no resources (`:401-410`). Clients still see that the group-version exists and can tell that the data might be wrong.
- **Deletion:** a removed APIService leads to `RemoveGroupVersion` (`:390`).

## Refresh loop

`Run` (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_discovery.go:450`):
- Workers drain `dirtyAPIServiceQueue`, re-queueing with rate limiting on error (`:496`).
- Every **1 minute**, every remote APIService is marked dirty and re-queued (`:505-518`). Thanks to ETags, most of these refreshes are cheap 304s.

## Patterns

- **Scatter-gather:** ask every backend, merge everything into one response.
- **Cache with conditional revalidation:** HTTP ETag and `If-None-Match`.
- **Serve stale on error:** prefer degraded data with a flag over a missing group-version.
- **Dirty queue plus periodic resync:** the standard controller work-queue loop, with a timer as a safety net.

## Try

- `kubectl get --raw /apis -H 'Accept: application/json;g=apidiscovery.k8s.io;v=v2;as=APIGroupDiscoveryList' | jq '.items[] | select(.metadata.name=="metrics.k8s.io")'`. Look for the `freshness` field.
- Scale metrics-server to 0, wait about 1 minute, and run the command again. The entry should become `Stale`.
- `kubectl api-resources -v=8 2>&1 | grep -E 'GET|Accept'`: kubectl makes a single discovery round trip.
