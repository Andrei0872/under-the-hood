# Default ServiceCIDR controller: events dropped after `Start` returns?

**Status:** open investigation. The code suggests it is a bug, but this has not been seen happening yet.

**Suspicion:** the controller that keeps the default `kubernetes` ServiceCIDR in line with the apiserver flags sets up an event broadcaster and shuts it down when `Start` returns. `Start` returns after the first successful sync and leaves a periodic sync loop running in the background. Any Event that loop tries to emit later is dropped and logged as an error.

## The code

`pkg/controlplane/controller/defaultservicecidr/default_servicecidr_controller.go`, in `Controller.Start`:

| Line | What happens |
|---|---|
| `:105-108` | Create the broadcaster and recorder, log events, and write events to the API (`StartRecordingToSink`) |
| `:109` | `defer c.eventBroadcaster.Shutdown()` runs when `Start` returns |
| `:120-128` | Block, polling every 100ms, until the first `sync()` succeeds. This blocks apiserver startup on purpose |
| `:131-136` | `go wait.Until(c.sync, c.interval, stopCh)`: the periodic loop keeps running |
| `:137` | `Start` returns, and the deferred `Shutdown()` fires |

The caller is a post-start hook: `pkg/controlplane/instance.go:369-380` (`start-kubernetes-service-cidr-controller`). It calls `controller.Start(hookContext)` synchronously and doesn't expect it to keep running.

## Why events would be dropped

1. `eventBroadcasterImpl.Shutdown` calls `Broadcaster.Shutdown()` and cancels the sink context (`staging/src/k8s.io/client-go/tools/record/event.go:283-286`).
2. `Broadcaster.Shutdown` closes `m.stopped` (`staging/src/k8s.io/apimachinery/pkg/watch/mux.go:256-262`).
3. After that, every `Eventf` call ends in `ActionOrDrop`, which returns `"broadcaster already stopped"` (`staging/src/k8s.io/apimachinery/pkg/watch/mux.go:235-239`).
4. `generateEvent` logs `Unable to record event (will not retry!)` and gives up (`staging/src/k8s.io/client-go/tools/record/event.go:462-466`).

Events that `sync()` emits in the background loop (lines 152, 177, 201, 218 and 238 of the controller) would be affected. For example: `KubernetesDefaultServiceCIDRInconsistent` at `:201`, emitted when the flags and the stored object disagree.

Events emitted **during** the first blocking poll are fine, because the broadcaster is still alive then.

## How to confirm

- **Breakpoint:** `staging/src/k8s.io/client-go/tools/record/event.go:464` in a running apiserver, then cause any warning in the background loop.
- **Logs:** look for `broadcaster already stopped` together with `default-servicecidr` in the kube-apiserver logs.
- **Causing a warning after startup:** one way is to make the stored ServiceCIDR's `Ready` condition differ from what the controller expects (path at `:210-218`), then wait for the next loop iteration (10s, set at `:61`).

## Open questions

- Is this known or fixed upstream? Search the kubernetes/kubernetes issues for "defaultservicecidr broadcaster shutdown".
- Compare with the controller's sibling `pkg/controlplane/controller/kubernetesservice/controller.go`. It has no recorder and splits `Start` from `Stop` (`:87`, `:113`), which avoids this problem.
- What would the fix look like? Probably tie the broadcaster's lifetime to `ctx` instead of to `Start`. Shut it down in a goroutine on `<-ctx.Done()`, or in the background loop's own exit path.

## Pattern

This is a **resource lifetime mismatch**. A resource's cleanup is scoped to a function (`defer`), but one of its users, the goroutine, outlives that function. It's the same class of bug as returning a closure that uses a file you already `defer f.Close()`d.
