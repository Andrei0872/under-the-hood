# Generated code with a hand-written override

**Idea:** a generator produces the repetitive code, and a person writes only the cases it can't work out. The hand-written version takes the place of the generated one, and can still call it.

## How Kubernetes conversions use it

| Function | Written by | Job |
|---|---|---|
| `autoConvert_X_To_Y` | always generated | copies the fields field by field |
| `Convert_X_To_Y` | generated, unless you write your own | the public function that gets registered |

If you write `Convert_X_To_Y`, the generator uses yours instead of creating the wrapper (`staging/src/k8s.io/code-generator/cmd/conversion-gen/main.go:30-60`).

## Example

The generated copy runs first, then the hand-written rules (`pkg/apis/core/v1/conversion.go:374-386`):

```go
func Convert_v1_Pod_To_core_Pod(in *v1.Pod, out *core.Pod, s conversion.Scope) error {
	if err := autoConvert_v1_Pod_To_core_Pod(in, out, s); err != nil { // generated copy
		return err
	}
	out.Annotations = dropInitContainerAnnotations(out.Annotations)    // hand-written rule
	// ...a negative TerminationGracePeriodSeconds is forced to 1
```

## When an override is needed

- **Behaviour rules:** the Pod conversion above.
- **A field doesn't exist on the other side:** the generator leaves a `requires manual conversion` warning (`pkg/apis/core/v1/zz_generated.conversion.go:5524`).
- **Different shapes:** CRD schemas move between spec level and per-version (`staging/src/k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1/conversion.go:73`).

## File layout

- `zz_generated.conversion.go`: generated, never edited (9,360 lines in `core/v1`).
- `conversion.go`: hand-written (568 lines in `core/v1`).
- `doc.go`: the `+k8s:conversion-gen=` tags that trigger generation, run by `hack/update-codegen.sh:536`.
