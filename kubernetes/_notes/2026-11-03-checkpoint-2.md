# kubernetes Questions — Checkpoint 2 (2026-11-03)

_Extracted from conversation since: 2026-10-28_

_**Try:** lines are the agent's suggestions. They weren't run unless marked otherwise._

---

## Logging & Output Streams

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/filterlatency/filterlatency.go#L70-70 -- where are logs written to? stdout? a file?
  - **Try:** `grep '"HTTP" verb=' /tmp/kube-apiserver.log | grep fl_ | head`
- re logs: why to stderr and not stdout?
  - **Try:** see where the running process's streams point:
    ```sh
    sudo ls -l /proc/$(pgrep -o kube-apiserver)/fd/1 /proc/$(pgrep -o kube-apiserver)/fd/2
    ```
- what does it mean they're buffered? buffered vs unbufferred?:
  ```
  Go's os.Stdout and os.Stderr are both
    unbuffered, and klog does its own buffering before either one (klog.go:52).
  ```
  - **Try:** watch the syscalls directly (needs `--v=3`, the local cluster's default):
    ```sh
    sudo strace -f -s 80 -e trace=write -p $(pgrep -o kube-apiserver) 2>&1 | grep '"HTTP"'
    ```
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1077-1077 - where do these logs go?

## API Priority and Fairness (APF)

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/util/flowcontrol/request/config.go#L76-78 -- there are 2 kinds of seats? mutating and list?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1019-1027 -- why does authorization needs to run after APF(app priority and fairness)? does it make sense to apply APF on an unanothorized requst?
  - **Try:** needs anonymous auth enabled and the default port 6443:
    ```sh
    # Expect a 403 with x-kubernetes-pf-* headers, so APF ran before the denial
    curl -sk -D- -o /dev/null https://localhost:6443/api/v1/secrets | grep -iE '^HTTP|x-kubernetes-pf'

    # Expect a 401 with no such headers, so APF never ran
    curl -sk -D- -o /dev/null -H 'Authorization: Bearer nope' https://localhost:6443/api/v1/secrets | grep -iE '^HTTP|x-kubernetes-pf'
    ```

## Handler Chain Filters

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1032-1034 -- is this a perfect example of AOL (aspect-oriented programming)?
  - **Try:** compare the filter latency metric with a denied impersonation. The count for `filter="impersonation"` shouldn't increase:
    ```sh
    kubectl get --raw /metrics | grep 'apiserver_request_filter_duration_seconds_count.*impersonation'
    kubectl get pods --as=nobody --as-group=nobody   # with a user who isn't allowed to impersonate
    ```
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1037-1037 -- what is the purpose of this?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1038-1047 -- tracing vs (trackStarted & trackCompleted) ?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1037-1041 -- withAudit vs WithFailedAuthenticationAudit?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1057-1057 -- what is WarningRecorder?
  - **Try:** `kubectl get componentstatuses` should print a deprecation warning that arrived this way.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1048-1048 -- what does it complete? ie, where is the corresponding trackStarted?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/filters/request_received_time.go#L26-28 -- why do we need to know this, ie when the request has reached the apiserver? tracking -> monitoring?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/filters/mux_discovery_complete.go#L40-40 -- what are these controllers?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/filters/audit_init.go#L44-47 -- can this already exist only if a proxy has already set up? what are some examples of such proxies?
  - **Try:** needs anonymous auth and port 6443. The response should echo your ID:
    ```sh
    curl -sk -D- -o /dev/null -H 'Audit-ID: my-id' https://localhost:6443/version | grep -i audit-id
    ```

## Timeouts & Panics

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/filters/timeout.go#L103-103 -- does this handle a panic case? why a panic can occur?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1061-1061 -- where does the timeout start and where does cancellation actually happens? is my answer here -- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1063-1063 ?

## Goroutines & WithRoutine

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1079-1082 -- which handlers will be run in a separate goroutine?
- elaborat on this. illustrate with a simple example.:
  ```
  The watch handler stores its serving function as a task instead of running it (endpoints/handlers/get.go:290-292). When the temporary goroutine exits, its stack memory is freed, and the
    original goroutine runs the task (routine.go:85-88). That keeps a long-lived watch from holding a stack grown during setup.
  ```
  - **Try** (the agent ran this demo; its scratchpad path may no longer exist): run it with `A` or `B`:
    ```sh
    cd /tmp/claude-501/-home-andrei-guest-src-under-the-hood-kubernetes/3ff1c38a-d7d3-45b2-a3ec-b9c33e32681d/scratchpad/routinedemo && ./demo A
    ```
  - **Try:** to see it in the apiserver, start it with `--feature-gates=APIServingWithRoutine=true`, open a watch, and compare goroutine dumps from `/debug/pprof/goroutine?debug=2`. The blocked watch's stack should be much shorter with the feature on.

## Server Construction & Shutdown

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L814-815 -- there are mainly for graceful shutdown purposes?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L866-877 -- why is there a need for the for loop? could there be a case where atomic.CompareAndSwapInt64 does not swaps the value successfully? why not?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L889-889 -- where can c.PostStartHooks be configured?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/hooks.go#L188-193 -- why a lock? can it be accessed by multiple goroutines?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L836-838 -- healthz vs readyz vs livez?
  - **Try:** `kubectl get --raw='/readyz?verbose'`, then the same for `/livez`.

## Discovery

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L841-841 -- what is this? what does discovery refer to? what is a discoverygroupmanager?
- i suppose it is different from: @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L860-860, which is useful for clients like kubetctl? but in what regard useful?
  - **Try:**
    ```sh
    kubectl proxy &
    curl -s localhost:8001/apis | head -20
    curl -s -H 'Accept: application/json;g=apidiscovery.k8s.io;v=v2;as=APIGroupDiscoveryList' localhost:8001/apis | head -40
    ```

## Routing & Server Chain

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/mux/pathrecorder.go#L221-221 -- not clear what it does.
- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apiserver/apiserver.go#L206-208 -- so, apiextension-server is reached via /apis, too?
  - **Try:** create a CRD, then compare a request to its path with one to a made-up path. To watch the routing, use `--v=5`, which logs each "satisfied by" decision (`handler.go:142`, `:152`).

## Profiling & Sampling

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/config.go#L1099-1099 -- what is contention profiling?
  - **Try:** with the flag on, `kubectl get --raw '/debug/pprof/block?debug=1' | head -30`
- 'all of them' implying that the smallest unit of measurement is nanoseconds?:
  ```
  SetBlockProfileRate(1) (line 1100) aims to sample about one event per nanosecond spent blocked (/usr/local/go/src/runtime/mprof.go:477-479), so effectively all of them
  ```
- events kept vs sampled?
