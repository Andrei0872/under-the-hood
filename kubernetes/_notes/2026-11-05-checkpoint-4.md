# kubernetes Questions — Checkpoint 4 (2026-11-05)

_Extracted from conversation since: 2026-11-03_

_**Try:** lines are the agent's suggestions. They weren't run unless marked otherwise._

---

## Equivalent Resources

- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/runtime/mapper.go#L97-97 -- what is the purpose of this? to my understanding: key = computed and includes in its final value resource and subresource; the r.resources map seems to map a key to a subresource and that to an array of actual resources (resources are 1:1 mappings from/from api groups?; e.g. customresourcedefinitions).
- subresources in a per-CRD registry -- what's this?
  - **Try:** set a breakpoint at `customresource_handler.go:753`, then run `kubectl get <your-crd-resource>` after the apiserver starts.
- why does not kinds[example.com/v2 widgets] exist?

## Storage Versions

- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/apis/meta/v1/types.go#L1206-1206 -- what problem does it solve?
  - **Try:** `kubectl get --raw /apis/apiextensions.k8s.io/v1 | jq '.resources[] | {name, storageVersionHash}'`
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L598-598 -- what's this API?

## API Groups & Web Services

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L197-197 -- will there be a new web service per API group?
- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/runtime/schema/group_version.go#L166-169 -- is this the canonical definition of an api group? meaning, api group = group + version? or is version a separate attribute?
  - **Try:** `kubectl get --raw /apis/apps` shows a group with its versions, and `/apis/apps/v1` shows one version's resources.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L202-207 -- from this, i undestand that an api group (e.g. apiextensions.k8s.io) can have multiple resources (customresourcedefinitons and customresourcedefinitions/status)? basically: api group -> multiple storage -> multiple paths -> multiple resources for the same group.
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/server/genericapiserver.go#L807-807 -- is this useful for kubectl mainly?

## Go: Pointers, Reflection, Embedding

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/registry/customresourcedefinition/etcd.go#L196-196 -- why does it have to be a pointer?
- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/runtime/scheme.go#L267-267 -- why does it have to be a pointer here, too? does a pointer help with reflection?
- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/runtime/scheme.go#L307-307 -- why is Interface().(Object) needed?
- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/registry/customresourcedefinition/etcd.go#L189-191 VS @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/registry/customresourcedefinition/etcd.go#L37-39 ? does it mean that REST implicitly implements whatever genericregistry.Store implemented, whereas StatusREST must (re)implement the interfaces explictily?

## Kinds & Internal Versions

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L262-271 -- from this, i infer that one object can have multiple kinds? give a concrete example.
- this is a kind wihtout a parent api group? is this possible? it is clearly a Kind, right?:
  ```
  ▾ kind k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = schema.GroupVersionKind {Group: "", Version: "v1", Kind: "CreateOptions"}
     Group string = ""
     Version string = "v1"
     Kind string = "CreateOptions"
  ```
- why does it have __internal as version?@kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L272-274 -- here it seems that __interal gets somehow converted to v1.:
  ```
  ▾ fqKind k8s.io/apimachinery/pkg/runtime/schema.GroupVersionKind = schema.GroupVersionKind {Group: "apiextensions.k8s.io", Version: "__internal", Kind: "CustomResourceDefinition"}
     Group string = "apiextensions.k8s.io"
     Version string = "__internal"
     Kind string = "CustomResourceDefinition"
  ```

## Conversion & Versions

- > Pattern: hub-and-spoke. Each version only converts to and from the hub (v1/zz_generated.conversion.go), so N versions need N converters instead of one per pair.

  elaborate on this, not very clear. give concrete examples.
  - **Try:** set a breakpoint at `v1/conversion.go:169`, then apply a multi-version CRD with identical schemas. `validationIdentical` should be `true`.
- so, a v1 request is converted to v1beta internally? why?
  - **Try:** `kubectl get crd <name> -o json | jq '[.spec.versions[] | has("schema")]'`
- how does beta differ?:
  ```
  ▾ apiGroupInfo.PrioritizedVersions []k8s.io/apimachinery/pkg/runtime/schema.GroupVersion = []schema.GroupVersion len: 2, cap: 2, [{Group: "apiextensions.k8s.io", Version: "v1"},{Group: "apiextensions.k8s.io", Version: "v1beta1"}]
   ▾ [0] k8s.io/apimachinery/pkg/runtime/schema.GroupVersion = schema.GroupVersion {Group: "apiextensions.k8s.io", Version: "v1"}
      Group string = "apiextensions.k8s.io"
      Version string = "v1"
   ▾ [1] k8s.io/apimachinery/pkg/runtime/schema.GroupVersion = schema.GroupVersion {Group: "apiextensions.k8s.io", Version: "v1beta1"}
      Group string = "apiextensions.k8s.io"
      Version string = "v1beta1"
  ```
  - **Try:** `kubectl get --raw /apis/apiextensions.k8s.io/v1beta1` should return 404, which shows it isn't served.
  - **Try:** `etcdctl get /registry/apiextensions.k8s.io/customresourcedefinitions/<name>` (assuming the default etcd prefix) should show `apiextensions.k8s.io/v1beta1` in the stored object.

## Code Generation

- @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1/zz_generated.deepcopy.go#L158-158 -- how is this file generated? and why? what problem does it solve?
- @kubernetes/_upstream/pkg/apis/core/v1/conversion.go -- is this generated, too?
  - **Try:** set a breakpoint at `conversion.go:380`, then run `kubectl apply --dry-run=server` on a Pod manifest. It should hit when the `v1` request is decoded to internal.

## Watch & Connect

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L431-432 -- why isnt customresourcedefinitions store a watcher? what is really a watcher?
  - **Try:** `kubectl get --raw /apis/apiextensions.k8s.io/v1 | jq '.resources[] | {name, verbs}'` should show `watch` only on the main resource.
- @kubernetes/_upstream/pkg/registry/core/pod/rest/subresources.go#L231-233 -- why do pods seem to be the only resources that implemenbt the Connecter interface? what is this interface used for?
  - **Try:** `kubectl get --raw /api/v1 | jq '.resources[] | select(.name | test("exec|portforward|proxy")) | {name, verbs}'` lists the `Connecter` subresources.

## Request Handling & Field Management

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L658-659 -- how do these defer?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L691-692 -- what is spec resource strategy? what is the meaning of all of this?
  @kubernetes/_upstream/staging/src/k8s.io/apiextensions-apiserver/pkg/registry/customresourcedefinition/strategy.go#L250-252 : perhaps related.
- @kubernetes/_upstream/staging/src/k8s.io/apimachinery/pkg/util/managedfields/internal/fieldmanager.go#L57-75 -- what is this? waht is hte purpsoe of this? what are fields, exactly?
  - **Try:** `kubectl get crd <name> -o yaml --show-managed-fields` shows real `managedFields`.

## Route Building & OpenAPI

- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L818-824 -- is this the builder pattern beautifully appleid?
- @kubernetes/_upstream/staging/src/k8s.io/apiserver/pkg/endpoints/installer.go#L819-824 -- are all of these useful for open api?
