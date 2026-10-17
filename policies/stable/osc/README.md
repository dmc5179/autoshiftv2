# osc AutoShift Policy

## Overview
Installs the sandboxed-containers-operator operator using AutoShift's ACM **PolicyGenerator** pattern. The
directory is a Kustomize source: `policy-generator-config.yaml` wraps the bare manifests under
`manifests/` into an ACM `Policy`, and pairs it with the hand-authored `placement.yaml`.

## Layout
```
osc/
  kustomization.yaml            # entrypoint: generators: [policy-generator-config.yaml]
  policy-generator-config.yaml  # the PolicyGenerator (policy graph, remediation, eval interval)
  placement.yaml                # Placement predicate (autoshift.io/osc) + tolerations
  manifests/
    operator-install/
      kustomization.yaml        # renders the shared components/operator-install chart (Namespace +
                                #   OperatorPolicy); per-operator ACM lookups are visible here
```
The operator-install renders the shared `components/operator-install` chart — edit the visible ACM
lookups in `manifests/operator-install/kustomization.yaml` to tune the subscription/version. Add
further CRs as new `policies[]` entries in `policy-generator-config.yaml` pointing at their own dirs.

## Test Locally
```bash
# Render the policy exactly as the CMP/CI does (needs: make install-policy-generator)
KUSTOMIZE_PLUGIN_HOME=$PWD/.tools/kustomize-plugin .tools/kustomize build \
  --enable-alpha-plugins --enable-helm --load-restrictor LoadRestrictionsNone \
  policies/stable/osc

# Full validation (helm render + hub/spoke template resolution + label contract)
cd tools && go test -tags integration -count=1 ./internal/resolver/...
```
The `${POLICY_NAMESPACE}`, `${REMEDIATION}`, `${EVAL_COMPLIANT}`, `${EVAL_NONCOMPLIANT}` tokens are
substituted per-deployment by the repo-server CMP before `kustomize build` runs; leave them as-is.

## Enable on Clusters
Labels are defined in values files only — never directly on managed clusters. The cluster-labels
policy propagates them, and this policy's `placement.yaml` selects clusters with
`autoshift.io/osc: 'true'`.

```yaml
# In autoshift/values/clustersets/hub.yaml (or another clusterset / per-cluster file)
hubClusterSets:
  hub:
    labels:
      osc: 'true'
      osc-subscription-name: 'sandboxed-containers-operator'
      osc-channel: 'stable'
      osc-source: 'redhat-operators'
      osc-source-namespace: 'openshift-marketplace'
      # osc-version: 'sandboxed-containers-operator.v1.x.x'  # Optional: pin to a specific CSV
```
`generate-operator-policy.sh --add-to-autoshift` adds these for you (and to `_example*.yaml`, which
the label-contract CI requires for every consumed `autoshift.io/*` key).

The ApplicationSet auto-discovers new directories under `policies/stable/*` (and `certified`/
`community`) — no manual registration required.

## Version Control
- **Automatic upgrades** within the channel by default.
- **Pin a version** with the `osc-version` label — a pinned version sets a manual
  install plan (`startingCSV` + `versions`), so upgrades become explicit.
```bash
# Find available CSV versions
oc get packagemanifests sandboxed-containers-operator -o jsonpath='{.status.channels[*].currentCSV}'
```

## Adding Configuration (operator CRs)
After the operator installs, add its Custom Resources as **bare manifests** — do NOT hand-write a
ConfigurationPolicy wrapper; PolicyGenerator generates it.

1. Explore the CRDs the operator installed:
   ```bash
   oc get pods -n openshift-sandboxed-containers-operator
   oc get crds | grep osc
   oc explain <CustomResourceName>
   ```
2. For a **static** CR, drop a bare manifest into `manifests/`:
   ```yaml
   # manifests/osc-config.yaml
   apiVersion: <operator apiVersion>
   kind: <CustomResource>
   metadata:
     name: osc-config
     namespace: openshift-sandboxed-containers-operator
   spec:
     setting: value
   ```
3. For a CR that needs **hub templates / loops / conditionals**, use a bare `object-templates-raw`
   manifest instead (PG still wraps it into one ConfigurationPolicy; `complianceType` lives inside):
   ```yaml
   # manifests/osc-config.yaml
   object-templates-raw: |
     - complianceType: musthave
       objectDefinition:
         apiVersion: <operator apiVersion>
         kind: <CustomResource>
         metadata:
           name: osc-config
           namespace: openshift-sandboxed-containers-operator
         spec:
           setting: '{{hub index .ManagedClusterLabels "autoshift.io/osc-setting" | default "default-value" hub}}'
   ```
4. If the config must be its **own** Policy (separate remediation, a dependency, or a different
   predicate), add a `policies[]` entry in `policy-generator-config.yaml` (with `dependencies:` on
   `policy-osc-operator-install`) and point it at the new manifest with its own
   `placement.placementPath`. `generate-policy.sh --dir policies/stable/osc` scaffolds this.

Document any new `autoshift.io/osc-*` label in `autoshift/values/clustersets/_example.yaml`
or the label-contract CI (`go test -tags integration`) fails with `Missing`.

### Readiness / status checks
A status assertion (e.g. CSV `phase: Succeeded`) can only be observed, so give it its own
`policies[]` entry with `remediationAction: inform` — never fold an inform check into an enforce
manifest (ACM's root action would clobber it).

## Reference Examples
- **Simple operator**: `policies/stable/cert-manager/` — bare Namespace + OperatorPolicy (this shape)
- **Multiple related policies / placements**: `policies/stable/advanced-cluster-security/`
- **Multiple config types**: `policies/stable/metallb/`
- **Storage cluster config**: `policies/stable/openshift-data-foundation/`

## Troubleshooting
- **Policy not applied**: `oc get managedcluster <cluster> --show-labels`; check the Placement
  (`oc get placement -n policies-autoshift`) and `oc describe policy policy-osc-operator-install`.
- **Operator install issues**: `oc get subscription,installplan -n openshift-sandboxed-containers-operator`;
  `oc get catalogsource -n openshift-marketplace`.
- **Render issues**: run the `kustomize build` above; hub templates use bare `{{hub … hub}}`
  delimiters (no Helm `{{ "{{hub" }}` escaping in PolicyGenerator manifests).

## Resources
- [Operator Documentation](https://operatorhub.io/operator/sandboxed-containers-operator)
- [AutoShift Developer Guide](../../../docs/developer-guide.md)
- [ACM PolicyGenerator](https://github.com/open-cluster-management-io/policy-generator-plugin)

## Optional, and it has two manual steps

OpenShift sandboxed containers provides VM-level (Kata) isolation *underneath* OpenShell's
kernel-enforced isolation. Agent Sandbox does not require it — enable it only if you want the second
layer.

Two things this policy cannot do for you:

1. The default Kata initramfs ships **without the `nf_tables` kernel modules**, which OpenShell's
   sidecar topology needs in order to intercept traffic inside the guest VM. Sandbox creation fails
   without them. The patch has to be applied separately, **and it is lost on every worker reboot**.
2. On bare metal the patch's ServiceAccount needs the privileged SCC.

A MachineConfig would be the durable answer to (1), but that is not written yet.

## Install mode

Verified against the catalog on OpenShift 4.22, `sandboxed-containers-operator` v1.13.1:

```
OwnNamespace=True  SingleNamespace=True  MultiNamespace=False  AllNamespaces=False
```

AllNamespaces is **not** supported, so this policy sets `targetNamespaces`. See the `rhbk` README
for what happens without it.
