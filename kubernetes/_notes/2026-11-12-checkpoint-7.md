# kubernetes Questions — Checkpoint 7 (2026-11-12)

_Extracted from conversation since: 2026-11-11_

---

## Control plane: storage providers & API groups

- @kubernetes/_upstream/pkg/controlplane/instance.go#L335-335 -- 20 rest providers == 20 API groups? is this understanding correct?
  - **Try:** `kubectl get --raw /apis | jq '.groups | length'`
- @kubernetes/_upstream/pkg/registry/core/rest/storage_core.go#L152-152 -- why is this called generic? could this mean it can be reused by other parts? which parts?
- got this list from here: @kubernetes/_upstream/pkg/controlplane/apiserver/apis.go#L140-140; wanna clarify: pods/status is a subresource, while pods is the resource, correct?
  ```
     [0] string = "bindings"
     [1] string = "componentstatuses"
     [2] string = "configmaps"
     [3] string = "endpoints"
     [4] string = "events"
     [5] string = "limitranges"
     [6] string = "namespaces"
     [7] string = "namespaces/finalize"
     [8] string = "namespaces/status"
     [9] string = "nodes"
     [10] string = "nodes/proxy"
     [11] string = "nodes/status"
     [12] string = "persistentvolumeclaims"
     [13] string = "persistentvolumeclaims/status"
     [14] string = "persistentvolumes"
     [15] string = "persistentvolumes/status"
     [16] string = "pods"
     [17] string = "pods/attach"
     [18] string = "pods/binding"
     [19] string = "pods/ephemeralcontainers"
     [20] string = "pods/eviction"
     [21] string = "pods/exec"
     [22] string = "pods/log"
     [23] string = "pods/portforward"
     [24] string = "pods/proxy"
     [25] string = "pods/resize"
     [26] string = "pods/status"
     [27] string = "podtemplates"
     [28] string = "replicationcontrollers"
     [29] string = "replicationcontrollers/scale"
     [30] string = "replicationcontrollers/status"
     [31] string = "resourcequotas"
     [32] string = "resourcequotas/status"
     [33] string = "secrets"
     [34] string = "serviceaccounts"
     [35] string = "serviceaccounts/token"
     [36] string = "services"
     [37] string = "services/proxy"
     [38] string = "services/status"
  ```
- what are the clients of the apiserver? apart from kubectl?

## Control plane controllers (kubernetes service, ServiceCIDR)

- @kubernetes/_upstream/pkg/controlplane/controller/kubernetesservice/controller.go#L93-94 -- what is the purpose of this? why need the endpoints to be reconciled?
  - **Try:** `kubectl get endpoints kubernetes -n default -o yaml`
- @kubernetes/_upstream/pkg/controlplane/instance.go#L360-360 -- is this useful in cases where the control plane has multiple apiservers? but why would that be the case? give concrete examples.
- @kubernetes/_upstream/pkg/controlplane/instance.go#L363-366 -- why other controllers, like DiscoveryController, not given this pre-shutdown hook?
- @kubernetes/_upstream/pkg/controlplane/controller/defaultservicecidr/default_servicecidr_controller.go#L105-109 -- what is the purpose of this?
- is it accurate to say that controllers act on API resources?
- kubelet also runs controllers on itself?

## Aggregator (kube-aggregator)

- @kubernetes/_upstream/cmd/kube-apiserver/app/aggregator.go#L34-34 -- what 'version' really means here? does it refer to apiserver version? I suppose not K8s real version.
  - **Try:** `kubectl get apiservice v2.autoscaling -o jsonpath='{.spec}'`
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L222-222 -- what serious consequences?
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L278-279 -- the purpose of this is to ensure that apiservices are aggregated, meaning that are to be seen by clients like kubectl?
  - **Try:** `kubectl get --raw /apis -v=8 2>&1 | grep -i accept`
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L283-284 -- elaborate on this. certificates are needed fror what? for apiserver<->external_api communication? what is the alternative of not using certificates?
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L290-290 -- isnt loadKeyPair() invoked already during @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L284-284 ?
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L303-304 -- do to these differ?
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L311-311 -- what does it do?
  - **Try:** `kubectl get --raw /metrics | grep aggregator_unavailable`
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L317-321 -- is this local because if there are multiple apiserver instances, each of them can have their own apiservices registered locally?
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L347-347 - is this somehow complementary to the local availability controller? @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L331-332 -- in which scenarious can this be replaced?
  - **Try:** `kubectl get apiservices | grep -v Local`
- re 23: what does it mean to probe the backend? which backend? the extenral backend you mean?
  - **Try:** `kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions}'`
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go#L364-364 -- what does it actually do?
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/apis/apiregistration/v1/types.go#L151-151 -- so.. each GroupVersion has a server? what is it really by a server?
  - **Try:** `kubectl get apiservice v1beta1.metrics.k8s.io -o yaml`, and compare it with `kubectl get apiservice v1.apps -o yaml`.
- re 25: does it mean I can create my own bakcned for, let's say, batch api group?
- are there open source examples of custom backends for core api groups?

## Generic apiserver: networking & mux

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/egressselector/egress_selector.go#L60-67 -- ControlPlane vs Cluster? my understanding: cluster = when an external request is meant to reach a kubelet? give concrete examples.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/mux/pathrecorder.go#L189-191 -- what does it mean to list it? does it refer to aggregation?
  - **Try:** `kubectl get --raw /`
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L761-761 -- so, a single action can have multiple routes? give a concrete example from this source code.

## Subresources & pods/exec streaming

- 'not every subresource is a stored view of the object' - this sounds abstract. what does it mean? what do pods/exec do? i suppose it does not store anything but mutate something, judging by your definition?
  - **Try:** `kubectl exec -v=8 <pod> -- true 2>&1 | grep -iE 'POST|upgrade'`
- 3 proxies are: kubectl, then apiserver, then kubelet; between them, at one end is the user (e.g. me) and the CRI. is this correct? why is the WS client converted to SPDY on the way to the kubelet?
- why would that command hang?
  - **Try:** `echo hi | kubectl exec -i <pod> -- cat`. To compare, force SPDY with `KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false`.

## client-go

- @kubernetes/_upstream/staging/src/k8s.io/client-go/transport/config.go#L82-85 -- is this just a golang trick? but the field is a function.
- @kubernetes/_upstream/staging/src/k8s.io/kube-aggregator/pkg/client/informers/externalversions/apiregistration/v1/apiservice.go#L99-101 -- what is a lister? lister vs informer?
