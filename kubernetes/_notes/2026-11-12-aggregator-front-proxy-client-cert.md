# Aggregator front-proxy client certificate

**Idea:** when kube-apiserver forwards a request to an extension apiserver (an aggregated API such as metrics-server), it does **not** forward the user's token. It sends the user's identity in `X-Remote-*` headers and proves "I am the trusted front proxy" with a TLS client certificate. The backend trusts the headers only when that certificate checks out.

## Where it's loaded

`staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go:283-299`, in `completedConfig.NewWithDelegate`:

| Line | What happens |
|---|---|
| `:283` | Only if `--proxy-client-cert-file` and `--proxy-client-key-file` are set (flag defined at `staging/src/k8s.io/kube-aggregator/pkg/cmd/server/start.go:91`) |
| `:284` | `NewDynamicServingContentFromFiles` reads and validates the pair. The constructor already loads it (`staging/src/k8s.io/apiserver/pkg/server/dynamiccertificates/dynamic_serving_content.go:72`) |
| `:290` | `RunOnce` loads it again. This is redundant but harmless: unchanged content returns early (`staging/src/k8s.io/apiserver/pkg/server/dynamiccertificates/dynamic_serving_content.go:109-113`) |
| `:293` | The APIService registration controller is added as a listener. When the cert changes, `Enqueue` re-adds every APIService (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiservice_controller.go:203-212`), so each proxy handler rebuilds its transport with the new cert |
| `:294` | `s.proxyCurrentCertKeyContent` returns the current pair |
| `:296-299` | A post-start hook keeps watching the files. This is cert rotation without a restart |

## Where it's used

**1. Proxying user requests**, in `staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_proxy.go`:
- `:220-231`: the transport config for a remote APIService has two separate sides:
  - `CertData` and `KeyData` come from the proxy cert. This is the **client** side: the aggregator proves who it is.
  - `CAData` comes from `apiService.Spec.CABundle`, and `ServerName` is `<svc>.<ns>.svc`. This is the **server** side: it verifies the backend.
- `:167` and `:178`: `NewAuthProxyRoundTripper` and `SetAuthProxyHeaders` attach the end user's name, UID, groups and extras as `X-Remote-User`, `X-Remote-Group` and `X-Remote-Extra-*`.

**2. Availability probes.** The remote availability controller receives the same cert function (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go:340`). It probes with `X-Remote-User: system:kube-aggregator` and `X-Remote-Group: system:masters` (`staging/src/k8s.io/kube-aggregator/pkg/controllers/status/remote/remote_available_controller.go:322`).

## The receiving side (the extension apiserver)

The extension apiserver runs the request-header authenticator (`staging/src/k8s.io/apiserver/pkg/authentication/request/headerrequest/requestheader.go:115-121`). It trusts `X-Remote-*` **only** if two things hold:
- The client cert chains to `--requestheader-client-ca-file` (`staging/src/k8s.io/apiserver/pkg/server/options/authentication.go:146`).
- The cert's CN is in `--requestheader-allowed-names`, when that list is set (`staging/src/k8s.io/apiserver/pkg/server/options/authentication.go:151`).

Extension servers usually don't get these as flags. They read them from the ConfigMap `kube-system/extension-apiserver-authentication` (`staging/src/k8s.io/apiserver/pkg/server/options/authentication.go:392`), which kube-apiserver publishes.

After authentication, the extension server **authorizes** the forwarded user. Usually it does this by asking kube-apiserver with a SubjectAccessReview (delegated authorization).

## Request flow

```
kubectl --(user token)--> kube-apiserver
   authn: token -> user "alice"     authz: may alice GET metrics.k8s.io?
   aggregator proxy --(mTLS: front-proxy client cert)--> metrics-server
        headers: X-Remote-User: alice, X-Remote-Group: ...
   metrics-server: cert signed by requestheader CA? -> trust headers -> user "alice"
                   authz via SubjectAccessReview -> serve
```

## Without the cert

- The aggregator connects without a client cert.
- The backend can't tell the aggregator apart from any other in-cluster caller. It must ignore `X-Remote-*`, because otherwise anyone could claim to be `system:masters`.
- The request becomes **anonymous**, and is rejected unless the backend allows anonymous access.
- The user's token isn't forwarded, so the backend can't fall back to token authentication either.

## Pattern

This is an **authenticating reverse proxy (front proxy)**. Authentication happens once at the edge, and identity is passed downstream in headers. The headers are trusted only because a separate channel, mTLS with a dedicated CA, proves the proxy's identity. Similar setups include oauth2-proxy with `X-Forwarded-User`, or Envoy with an ext_authz filter.

## Try

- `kubectl -n kube-system get cm extension-apiserver-authentication -o yaml`. Look for `requestheader-client-ca-file` and the `requestheader-*-headers` keys.
- `ps aux | grep kube-apiserver | tr ' ' '\n' | grep -E 'proxy-client|requestheader'` on a control-plane node.
- `openssl x509 -noout -subject -issuer -in <proxy-client-cert-file>`. The subject CN should match `requestheader-allowed-names`.
