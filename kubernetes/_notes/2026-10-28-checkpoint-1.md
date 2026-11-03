# kubernetes Questions — Checkpoint 1 (2026-10-28)

_Extracted from conversation since: beginning_

---

## Loopback Client & TLS

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/options/serving_with_loopback.go#L76-76 -- so, the loopback client is given the certificate (which contains both the CA and the leaf certificate). is stores the DER bytes at CAData. is this basically the way for a client to know of a CA?
- in browsers (who are also clients), for instance, they also need to store the CA. is the similar thing happening here?
- but why does the loopback client store the leaf certificate, too?
- this part is responsible for authentication. for authz, the client will use that UUID token. correct?

## client-go: Clientset, REST Config, API Groups

- @kubernetes/_upstream/staging/src/k8s.io/client-go/kubernetes/clientset.go#L145-202 -- are these all the API groups?
- i suppose tha all these entities are concerned with the apiserver. why are CRDs not there?
- these clients are not for apiserver <-> etcd communication, but for 'users' <-> apiserver communication?
- @kubernetes/_upstream/staging/src/k8s.io/client-go/rest/config.go#L361-363 -- what's this?
- @kubernetes/_upstream/staging/src/k8s.io/client-go/rest/config.go#L124-126 -- what is a burst throttle?
- @kubernetes/_upstream/staging/src/k8s.io/client-go/kubernetes/clientset.go#L523-531 -- how do these 3 diff versions differ? is this also a way to roll out new versions of api groups?
- @kubernetes/_upstream/staging/src/k8s.io/api/storage/v1/register.go#L46-64 -- these are all the kinds of the storage.k8s.io group?

## Scheme & API Versioning

- @kubernetes/_upstream/pkg/controlplane/apiserver/config.go#L164-164 -- wht does legacyscheme.Scheme contain? what are gvkToType and typeToGVK maps? and why do they have so many items?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/options/api_enablement.go#L109-115 - what is an emulated version?

## Informers, Reflector & Cache

- @kubernetes/_upstream/pkg/controlplane/apiserver/config.go#L159-159 -- so what exactly is an informer? i notice they concern the clients. the interface of the sharedInformerFactory seems to also have methods like Events(), which themselves correspond to API groups. correct? is an informer just a client-side cache mechanism?
- re resync period: why would a value be resent to its handler? what is the purpose?
- so, what is the purpose of the reflector?
- @kubernetes/_upstream/staging/src/k8s.io/client-go/informers/core/v1/node.go#L92-92 -- what is a cache indexer?
- database secondary index?? give me a concrete example of how that namespace cache indexer works in practice.

## API Priority and Fairness (APF)

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/options/feature.go#L81-85 -- this is a bit confusing. FlowControl is a prop of the server config. there, it uses the flowControl client (is this a client whose server is not apiserver?); it also makes use of informers, which I dont' know that they do yet. and all this block seems to create a controller?
- FlowSchena and PriorityLevelConfiguration are, first of all, kinds. correct? what is their api group?
- then, i suppose these values can change in real time (e.g. an admin changes something related to these 2 kinds) and the changes must be reflected in a real, already-running cluster -> this is the reason a controller exists. correct?
- then, when a new request from a user (e.g kubectl or a remote controller) comes in, the new FlowSchema/PriorityLevelConfiguration changes will be applied. is this reasoning correct?

## Authentication

- s.ClientCA string = "/var/run/kubernetes/client-ca.crt" -- is this also generated before starting apiserver?
- ClientCAFile string = "/var/run/kubernetes/request-header-ca.crt" -- how is this different than client-ca.crt
- what is the ourpose of @kubernetes/_upstream/pkg/kubeapiserver/options/authentication.go#L585-585
- what about:
  ```
  ▾ o.ServiceAccounts.KeyFiles []string = []string len: 1, cap: 1, ["/tmp/local-up-cluster.sh.oiWIy4/kube-serviceaccount.key"]
     [0] string = "/tmp/local-up-cluster.sh.oiWIy4/kube-serviceaccount.key"
  ```
- @kubernetes/_upstream/pkg/kubeapiserver/options/authentication.go#L626-626 -- what are webhooks?
- @kubernetes/_upstream/pkg/kubeapiserver/options/authentication.go#L696-696 -- what is this serviceaccountcontroller? does it follow the same pattern as apfcontroller, in the sense that serviceaccountcontroller is responsible for holding the most up-to-date changes in the config such that ServiceAccountTokenGetter will in turn hold the latest value when serving requests. in fact, serviceaccountcontroller seems to only retrieve the data on demand and not watch for changes. shes some ligh ton this.
- @kubernetes/_upstream/pkg/kubeapiserver/authenticator/config.go#L112-112 -- what exactly are these header requests?
- @kubernetes/_upstream/pkg/kubeapiserver/authenticator/config.go#L125-125 -- this is an authenticator; requestheader authentticator has a verificator type; what's the difference?
- @kubernetes/_upstream/pkg/kubeapiserver/authenticator/config.go#L169-170 -- why this?
- re 10: hot reload? basically, i can change a file on the fly and the program picks up the changes?
- @kubernetes/_upstream/pkg/kubeapiserver/authenticator/config.go#L201-201 -- when does apiserver require websockets?
- @kubernetes/_upstream/pkg/kubeapiserver/authenticator/config.go#L149-149 -- so, there is a diff between service accounts tokens and jtw tokens?
- @kubernetes/_upstream/pkg/kubeapiserver/options/authentication.go#L728-728 -- what can this file contain?
- elaborate on what a TokenRequest is.

## Authorization (Node, RBAC)

- @kubernetes/_upstream/pkg/kubeapiserver/authorizer/config.go#L107-107 -- what exactly are resource slices?
- @kubernetes/_upstream/pkg/kubeapiserver/authorizer/config.go -- why a graph?
- @kubernetes/_upstream/plugin/pkg/auth/authorizer/rbac/bootstrappolicy/policy.go#L190-244 -- explain a bit about policy rules.
- @kubernetes/_upstream/pkg/kubeapiserver/authorizer/config.go#L134-134 -- from this, i understand that rbac rules also get stored in etcd?
- @kubernetes/_upstream/plugin/pkg/auth/authorizer/node/node_authorizer.go#L48-56 -- how can this be read?
- why would kubelet ask for a secret?

## Audit & Discovery

- /tmp/local-up-cluster.sh.BEKQ1e/kube-audit-policy-file -- what about this?
- @kubernetes/_upstream/pkg/controlplane/apiserver/config.go#L239-239 -- what is this?
