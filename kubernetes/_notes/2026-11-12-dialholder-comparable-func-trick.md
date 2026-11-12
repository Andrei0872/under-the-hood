# DialHolder: making a func usable as a map key

**Idea:** Go func values can't be compared, so they can't go into a map key. Wrap the func in a small struct and keep a **pointer** to it. Pointers are comparable by address, so the key now compares by identity: "is this the same holder?"

## The problem

client-go caches `*http.Transport`s, so clients with the same TLS and dial settings share one connection pool:

```go
// staging/src/k8s.io/client-go/transport/cache.go:37-40
type tlsTransportCache struct {
	mu         sync.Mutex
	transports map[tlsCacheKey]*http.Transport
}
```

The key has to include the custom dial function, because two transports that dial differently must not be shared. But a struct with a func field can't be used as a map key:

```go
type key struct{ dial func(ctx context.Context, network, addr string) (net.Conn, error) }
m := map[key]int{} // compile error: invalid map key type key
```

The spec allows comparing funcs only with `nil`.

## The trick

```go
// staging/src/k8s.io/client-go/transport/config.go:82-85
// DialHolder is used to make the wrapped function comparable so that it can be used as a map key.
type DialHolder struct {
	Dial func(ctx context.Context, network, address string) (net.Conn, error)
}
```

The cache key stores `*DialHolder`, not the func:

```go
// staging/src/k8s.io/client-go/transport/cache.go:61-63
	// these functions are wrapped to allow them to be used as map keys
	getCert *GetCertHolder
	dial    *DialHolder
```

`GetCertHolder` (`staging/src/k8s.io/client-go/transport/config.go:157-160`) applies the same trick to the TLS client-cert callback.

## Compare: the func that wasn't wrapped

`Config.Proxy` is a plain func. Because of that, any config that sets it **can't be cached at all**:

```go
// staging/src/k8s.io/client-go/transport/cache.go:158-161
	if c.Proxy != nil {
		// cannot determine equality for functions
		return tlsCacheKey{}, false, nil
	}
```

So the cache has three outcomes: hit, miss and "uncacheable" (`staging/src/k8s.io/client-go/transport/cache.go:89-94`).

## The catch: identity, not equality

Two holders that wrap the *same* func are *different* keys. The cache only helps if callers reuse a single holder.

- **Done right:** the aggregator builds one holder at startup (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/apiserver.go:237` or `:240`). It passes that same pointer into the transport config of every APIService proxy (`staging/src/k8s.io/kube-aggregator/pkg/apiserver/handler_proxy.go:230`), so all of them share cached transports.
- **Easy to get wrong:** converting a `rest.Config` makes a new holder each time (`staging/src/k8s.io/client-go/rest/transport.go:114-116`). Two `rest.Config`s with the same `Dial` func therefore never share a cached transport, and every conversion creates a new cache entry.

## Takeaways

- Use it when you need a func in a map key or another comparison, and "same instance" is the meaning you want.
- The cost is that callers must hold on to and share the pointer, or the cache quietly fills with duplicates. Watch the `TransportCreateCalls` hit/miss metric (`staging/src/k8s.io/client-go/transport/cache.go:89-92`).
- The alternative is an explicit ID (a string name for each dialer). That is more work for callers but gives value semantics.

## Try

```go
package main

import "fmt"

type H struct{ F func() }

func main() {
	f := func() {}
	a, b := &H{f}, &H{f}
	m := map[*H]int{a: 1}
	_, okA := m[a]
	_, okB := m[b]
	fmt.Println(okA, okB) // true false: same func, different holder
}
```
