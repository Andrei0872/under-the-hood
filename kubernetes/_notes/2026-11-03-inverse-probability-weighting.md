# Inverse probability weighting

**Idea:** when you record only a random subset of events, make each recorded event count as `1 / (its chance of being recorded)`. It then stands in for the events that were dropped, so totals stay correct on average. It's also known as the Horvitz-Thompson estimator.

## Why it works

An event recorded with probability `p` and weight `1/p` contributes, on average:

```
p * (1/p) + (1 - p) * 0 = 1
```

That's exactly one event, whatever `p` is. So events can have different chances of being recorded without biasing the total.

## Where it shows up: Go's block profile

The block profile keeps long waits and samples short ones, so it records few short events without undercounting them. Paths are under `/usr/local/go/src/runtime/` (Go 1.27.2).

**Sampling** (`mprof.go:511-514`), with `cycles` as the event's length in CPU ticks:

| Event | Chance of being kept |
|---|---|
| `cycles >= rate` | 100% |
| `cycles < rate` | About `cycles / rate` |

**Weighting** (`saveBlockEventStack`, `mprof.go:786-808`):

```go
if which == blockProfile && cycles < rate {
    bp.count += float64(rate) / float64(cycles) // 1/p
    bp.cycles += rate                           // cycles * 1/p
} else if which == mutexProfile {
    bp.count += float64(rate)
    bp.cycles += rate * cycles
} else {
    bp.count++
    bp.cycles += cycles
}
```

The code comment at `mprof.go:795` states the rule: "We scale the events by 1 / (probability the event was sampled)."

The mutex profile uses the same idea with a different chance. Every event has a `1/rate` chance, whatever its length, so the weight is always `rate` (`mprof.go:794`, `:800-802`).

## Worked example

Rate of 1,000 ticks, and 100 events of 10 ticks each, which is 1,000 ticks of real blocking:

1. Each event has a 10/1,000 = 1% chance of being kept, so on average 1 of the 100 is kept.
2. That event's weight is 1,000/10 = 100, so it adds 100 to `count` and 1,000 to `cycles`.
3. The profile shows 100 events and 1,000 ticks, matching what happened.

## Limits

- **It's only right on average:** any single run can land above or below the true total, because one kept event can stand in for many.
- **Very small chances make it noisier:** if `p` is tiny, each kept event has a huge weight, so whether one happens to be kept moves the total a lot.
- **`p` has to be known:** the weight comes straight from `p`, so a wrong `p` gives wrong totals.
- **Nothing is scaled when every event is kept:** with `SetBlockProfileRate(1)`, as in kube-apiserver's `--contention-profiling` (`staging/src/k8s.io/apiserver/pkg/server/config.go:1100`, under `kubernetes/_upstream/`), every event has `cycles >= rate`, so the profile shows measured values.
