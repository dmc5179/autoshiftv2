# Adding a platform

AutoShift supports Amazon Web Services, VMware vSphere, and bare metal. Four policy directories
are platform-specific: `infra-nodes`, `worker-nodes`, `storage-nodes`, and `cluster-install`.
Everything else discovers what it needs at reconcile time and is platform-neutral.

This page is the checklist for adding a fifth. It is derived from the commits that added vSphere,
restated against the current repository layout.

## Before starting

Confirm the platform has a Machine API provider. The node policies clone a worker `MachineSet`, so
a platform without one cannot have them at any level of effort. Amazon Web Services, Microsoft
Azure, IBM Cloud, Google Cloud, vSphere, Nutanix, and OpenStack qualify. Oracle Cloud
Infrastructure does not: it is an external platform with no Machine API or Cluster API provider,
so only `cluster-install` could ever apply to it.

Pick one name and use it in all four places that must agree:

- `$validPlatforms` in `autoshift/templates/_validate-cluster-install.tpl`
- the `autoshift.io/<component>-provider` values in each `placement-<platform>.yaml`
- the filename suffix of `autoshift/values/clusters/_example-cluster-install-<platform>.yaml`
- the `shared:` list in `.github/config-key-conventions.yaml`

vSphere uses `vmware` as its platform string and `vsphere` as its config key. That split is
historical. Avoid repeating it.

## Node policies

For each of `infra-nodes`, `worker-nodes`, and `storage-nodes`:

1. Add `manifests/create-<component>-<platform>.yaml`. Start from the closest existing provider
   rather than from nothing. The AWS manifests read a zone from
   `providerSpec.value.placement.availabilityZone`; the vSphere manifests derive it from the
   `MachineSet` name, because `VSphereMachineProviderSpec` has no zone field and encodes placement
   through `workspace` and `network` instead. A platform whose provider spec carries `zone`
   directly is closer to the AWS shape.
2. Add `placement-<platform>.yaml`. Copy an existing one and change two things: `metadata.name`,
   and the value under the `autoshift.io/<component>-provider` match expression.
3. Register both in `policy-generator-config.yaml` as a new `policies[]` entry.

Policy names are capped at 40 characters, enforced by `TestPolicyNameLengths`. Abbreviate the
component rather than the directory when a generated name is too long, following the existing
`acs`, `virt`, `nfd`, and `rhtas` precedent.

Inherit cluster-specific provider fields from the base worker rather than reconstructing them.
Subnet identifiers, security groups, and image references cannot be derived from the
infrastructure name on a cluster installed into a pre-existing network.

## Cluster install

Add `manifests/<platform>.yaml`, modelled on `manifests/vmware.yaml`. The body is a hub-side
`range` over rendered-config `ConfigMap` resources, not a Helm loop over values. Guard the whole
body so it renders to nothing for other platforms:

```
{{- if and (eq (index $ci "createCluster" | default "") "true")
           (eq $platform "<platform>")
           (not (empty (index $config "<configkey>"))) }}
```

Register it in `policy-generator-config.yaml`. Do not add a placement: every `cluster-install`
policy shares the one set in `policyDefaults`.

## Two files that are easy to miss

Both of these fail the build in ways that do not name the platform as the cause.

### The cluster-install validator

`autoshift/templates/_validate-cluster-install.tpl` holds an allowlist:

```
{{- $validPlatforms := list "baremetal" "aws" "vmware" }}
```

A platform missing from that list makes `helm template ./autoshift` fail for any values file that
declares it. Add the platform, a `$valid<Platform>Keys` list, and an `if eq $platform` validation
block modelled on the vSphere one. The key list is a strict allowlist, so any configuration key
left out of it produces `is not a recognized field` at render time.

`TestAutoshiftChart_ClusterInstallExamples` exists to catch exactly this.

### The config key conventions file

A new top-level configuration key must be added to the `shared:` list in
`.github/config-key-conventions.yaml`, or `TestConfigKeyConventions` reports it as unmapped.

## Values and examples

Add `autoshift/values/clusters/_example-cluster-install-<platform>.yaml`.

This file is load-bearing for continuous integration, not documentation. The test harness
discovers platforms by globbing it: the platform key comes from the filename suffix, and each file
produces its own resolution profile with the node-provider labels pinned to that name. Populate it
fully. Commented-out keys reduce coverage.

Update the three `*-nodes-provider` comments in `autoshift/values/clustersets/_example.yaml`.
Declare any new `autoshift.io/` label there as well, or the label contract test fails. Reusing the
existing sizing labels requires no declaration work.

## Test fixtures

| File | What to add |
|---|---|
| `tools/testdata/cluster-openshift-resources.yaml` | Provider spec fields on **both** worker `MachineSet` stubs. The file is a deliberate multi-provider hybrid so that every per-provider policy resolves against the same object. |
| `tools/testdata/cluster-secrets.yaml` | A credentials `Secret` matching the `credentialRef` in the example file. |
| `tools/testdata/acs-managedclusters.yaml` | A `ManagedCluster` named `lint-cluster-<variant>`. |
| `tools/testdata/acs-secrets.yaml` | A matching `crs-lint-cluster-<variant>` `Secret`. |
| `tools/internal/resolver/e2e_test.go` | One `assertContains` marker proving the install policy body rendered. |

The last two rows are the easiest to miss. They key off the variant name derived from the example
filename, and nothing in the platform code refers to them.

Everything else in `e2e_test.go` is glob-driven and needs no change.

## Documentation and housekeeping

- `docs/cluster-install.md`: the platform list, the policy list, the diagram, the `platform:`
  field comment, and a platform-specific section
- `docs/values-reference.md`: the `*-nodes-provider` rows
- `README.md`: the two places that enumerate platforms
- `mkdocs.yaml`: only when adding a page, not when editing one
- `.vale/styles/config/vocabularies/AutoShift/accept.txt`: the platform name, if Vale rejects it
- `.gitleaks.toml`: only if an example contains a credential-shaped literal. Prefer
  `@example.com`, which is already allowed.

`versions.yaml` needs no change. Nothing in `scripts/` or the `Makefile` needs one either.

## Validate

```bash
make install-policy-generator
cd tools && go test -tags integration ./... -count=1
```

That is the command continuous integration runs.

## Known gap in the shared node manifests

The create path is per-provider. The remove and readiness manifests are not, and they read
`providerSpec.value.placement.availabilityZone`, which exists only on Amazon Web Services. Their
placements select on `autoshift.io/<component>-nodes` with no provider predicate, so they are
already placed on vSphere clusters, where that field is absent.

A new platform inherits the same mismatch. Decide whether to make the shared manifests
provider-tolerant or to add provider predicates to their placements before adding a fourth
provider, rather than after.
