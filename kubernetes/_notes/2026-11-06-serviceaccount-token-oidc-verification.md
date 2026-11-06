# Verifying a ServiceAccount token like an outside service (OIDC)

**Idea:** a pod already has an identity, its ServiceAccount token. An outside service can check that token using only public data the apiserver publishes, without calling the apiserver and without sharing a secret with the cluster.

## The problem it solves

A pod needs to call something outside the cluster: object storage, Vault, a database, or your own service in another cluster. That service asks, "who are you?"

| Approach | Downside |
|---|---|
| Put a long-lived password or API key in a Secret | Can leak, never expires, must be rotated by hand, and every pod with the Secret looks the same |
| Callee calls the apiserver's TokenReview API to check the token (`pkg/registry/authentication/tokenreview/storage.go:69`) | Callee must be able to reach the apiserver and have permission to call it, for every token it checks |
| **Callee verifies the token's signature itself** (this flow) | Callee must reach two public JSON documents, which can be copied elsewhere |

## Roles

| Role | Who | Job |
|---|---|---|
| Issuer, also called the OpenID Provider | kube-apiserver | Signs tokens and publishes the public keys |
| Bearer | The pod | Presents the token |
| Relying party | The outside service | Checks the token, then decides what the pod may do |

## Standards involved

It's the token-verification part of **OpenID Connect (OIDC)**. No OAuth 2.0 login or redirect flow takes place.

| Piece | Standard | Code |
|---|---|---|
| The token | JWT, RFC 7519 | claims built in `pkg/serviceaccount/claims.go:70` |
| `/.well-known/openid-configuration` | OIDC Discovery 1.0 | `pkg/serviceaccount/openidmetadata.go:39-41`, fields at `:200-212` |
| `/openid/v1/jwks` | JWK Set, RFC 7517 | `pkg/routes/openidmetadata.go:105-107` |

## Flow

```
setup (once): relying party is told "trust issuer <iss> for audience <aud>"

pod ── token ──> relying party
                   1. decode the token (no signature check yet), read "iss" and "kid"
                   2. GET <iss>/.well-known/openid-configuration  -> jwks_uri
                   3. GET <jwks_uri>                              -> public keys
                   4. pick the key whose "kid" matches, check the signature
                   5. check iss == trusted issuer, aud contains <aud>, exp in the future
                   6. map "sub" (system:serviceaccount:<ns>:<name>) to permissions
```

Steps 2-3 are cached, and the `Cache-Control: max-age` header tells the relying party for how long (`pkg/routes/openidmetadata.go:98`).

## Where things come from in this cluster

- **Issuer and `jwks_uri`:** `https://kubernetes.default.svc` and `.../openid/v1/jwks` (`hack/local-up-cluster.sh:682-683`). That address only resolves inside the cluster, so from the host use `kubectl get --raw`.
- **Signing key:** `--service-account-signing-key-file` (`hack/local-up-cluster.sh:684`).
- **Public keys served in the JWKS:** loaded from `--service-account-key-file` (`pkg/kubeapiserver/options/authentication.go:603-613`).
- **Who can read the discovery endpoints:** all ServiceAccounts by default, not anonymous users (`plugin/pkg/auth/authorizer/rbac/bootstrappolicy/policy.go:552-558`, `:701`).
- **Default audience when none is requested:** the apiserver's own audiences (`pkg/registry/core/serviceaccount/storage/token.go:117-118`), which default to the issuer (`pkg/kubeapiserver/options/authentication.go:593-594`).

## Exercise: be the relying party

Work through the steps and answer the questions before looking anything up.

1. **Get a token** for a made-up audience:
   ```sh
   kubectl create token default --audience=my-service --duration=10m > /tmp/sa.jwt
   ```
   - The token has three parts separated by dots. What is each one?
2. **Read it without verifying it.** Decode the first two parts, which are base64url (base64 with `-_` instead of `+/`, padding removed).
   - Which header field tells you which key signed it?
   - Find `iss`, `sub`, `aud`, `exp` and the `kubernetes.io` claims. Compare them with `pkg/serviceaccount/claims.go:52-62`.
3. **Discover the keys:**
   ```sh
   kubectl get --raw /.well-known/openid-configuration
   kubectl get --raw /openid/v1/jwks
   ```
   - Does `jwks_uri` match the flag in `hack/local-up-cluster.sh:683`?
   - Which key in the set matches your token's `kid`?
4. **Verify the signature yourself**, using Python's standard library only, with no JWT library.
   - Hint: for RS256 (RSA signature over SHA-256), `n` and `e` from the JWK are big-endian integers. Compute `pow(signature_as_int, e, n)`; the last 32 bytes of the result should equal `sha256(part1 + "." + part2)`.
5. **Check the claims as a relying party would.**
   - Verify the token you got with `--audience=my-service`, but expect audience `other-service`. Should that pass?
   - Wait for it to expire (or use `--duration=10m` and come back). What fails?
6. **Compare with the apiserver's own check.** Send the token to TokenReview:
   ```sh
   kubectl create -o yaml -f - <<EOF
   apiVersion: authentication.k8s.io/v1
   kind: TokenReview
   spec:
     token: $(cat /tmp/sa.jwt)
     audiences: ["my-service"]
   EOF
   ```
   - What does TokenReview know that your offline check in step 4 can't? Hint: bound tokens and `pkg/serviceaccount/jwt.go:403`.

## Where to read next

- How the apiserver checks the same tokens: `pkg/serviceaccount/jwt.go:227`.
- How the pod gets its token file: `plugin/pkg/admission/serviceaccount/admission.go:416`, then `pkg/kubelet/token/token_manager.go:71`.
