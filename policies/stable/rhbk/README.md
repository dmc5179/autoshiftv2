# rhbk AutoShift Policy

## Overview
Installs the rhbk-operator operator using AutoShift's ACM **PolicyGenerator** pattern. The
directory is a Kustomize source: `policy-generator-config.yaml` wraps the bare manifests under
`manifests/` into an ACM `Policy`, and pairs it with the hand-authored `placement.yaml`.

## Layout
```
rhbk/
  kustomization.yaml            # entrypoint: generators: [policy-generator-config.yaml]
  policy-generator-config.yaml  # the PolicyGenerator (policy graph, remediation, eval interval)
  placement.yaml                # Placement predicate (autoshift.io/rhbk) + tolerations
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
  policies/stable/rhbk

# Full validation (helm render + hub/spoke template resolution + label contract)
cd tools && go test -tags integration -count=1 ./internal/resolver/...
```
The `${POLICY_NAMESPACE}`, `${REMEDIATION}`, `${EVAL_COMPLIANT}`, `${EVAL_NONCOMPLIANT}` tokens are
substituted per-deployment by the repo-server CMP before `kustomize build` runs; leave them as-is.

## Enable on Clusters
Labels are defined in values files only — never directly on managed clusters. The cluster-labels
policy propagates them, and this policy's `placement.yaml` selects clusters with
`autoshift.io/rhbk: 'true'`.

```yaml
# In autoshift/values/clustersets/hub.yaml (or another clusterset / per-cluster file)
hubClusterSets:
  hub:
    labels:
      rhbk: 'true'
      rhbk-subscription-name: 'rhbk-operator'
      rhbk-channel: 'stable-v26.6'
      rhbk-source: 'redhat-operators'
      rhbk-source-namespace: 'openshift-marketplace'
      # rhbk-version: 'rhbk-operator.v1.x.x'  # Optional: pin to a specific CSV
```
`generate-operator-policy.sh --add-to-autoshift` adds these for you (and to `_example*.yaml`, which
the label-contract CI requires for every consumed `autoshift.io/*` key).

The ApplicationSet auto-discovers new directories under `policies/stable/*` (and `certified`/
`community`) — no manual registration required.

## Version Control
- **Automatic upgrades** within the channel by default.
- **Pin a version** with the `rhbk-version` label — a pinned version sets a manual
  install plan (`startingCSV` + `versions`), so upgrades become explicit.
```bash
# Find available CSV versions
oc get packagemanifests rhbk-operator -o jsonpath='{.status.channels[*].currentCSV}'
```

## Adding Configuration (operator CRs)
After the operator installs, add its Custom Resources as **bare manifests** — do NOT hand-write a
ConfigurationPolicy wrapper; PolicyGenerator generates it.

1. Explore the CRDs the operator installed:
   ```bash
   oc get pods -n rhbk-operator
   oc get crds | grep rhbk
   oc explain <CustomResourceName>
   ```
2. For a **static** CR, drop a bare manifest into `manifests/`:
   ```yaml
   # manifests/rhbk-config.yaml
   apiVersion: <operator apiVersion>
   kind: <CustomResource>
   metadata:
     name: rhbk-config
     namespace: rhbk-operator
   spec:
     setting: value
   ```
3. For a CR that needs **hub templates / loops / conditionals**, use a bare `object-templates-raw`
   manifest instead (PG still wraps it into one ConfigurationPolicy; `complianceType` lives inside):
   ```yaml
   # manifests/rhbk-config.yaml
   object-templates-raw: |
     - complianceType: musthave
       objectDefinition:
         apiVersion: <operator apiVersion>
         kind: <CustomResource>
         metadata:
           name: rhbk-config
           namespace: rhbk-operator
         spec:
           setting: '{{hub index .ManagedClusterLabels "autoshift.io/rhbk-setting" | default "default-value" hub}}'
   ```
4. If the config must be its **own** Policy (separate remediation, a dependency, or a different
   predicate), add a `policies[]` entry in `policy-generator-config.yaml` (with `dependencies:` on
   `policy-rhbk-operator-install`) and point it at the new manifest with its own
   `placement.placementPath`. `generate-policy.sh --dir policies/stable/rhbk` scaffolds this.

Document any new `autoshift.io/rhbk-*` label in `autoshift/values/clustersets/_example.yaml`
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
  (`oc get placement -n policies-autoshift`) and `oc describe policy policy-rhbk-operator-install`.
- **Operator install issues**: `oc get subscription,installplan -n rhbk-operator`;
  `oc get catalogsource -n openshift-marketplace`.
- **Render issues**: run the `kustomize build` above; hub templates use bare `{{hub … hub}}`
  delimiters (no Helm `{{ "{{hub" }}` escaping in PolicyGenerator manifests).

## Resources
- [Operator Documentation](https://operatorhub.io/operator/rhbk-operator)
- [AutoShift Developer Guide](../../../docs/developer-guide.md)
- [ACM PolicyGenerator](https://github.com/open-cluster-management-io/policy-generator-plugin)

## When you need this

Required for any **remote** OpenShell gateway: gateways authenticate CLI users over OIDC, not mTLS.
Port-forward access works without it, but that is an evaluation path only.

OpenShell's own demo material deploys a raw `keycloak-rhel9` image; its validation table says to use
the RHBK operator in production, which is what this policy installs.

## Install mode

Verified against the catalog on OpenShift 4.22, `rhbk-operator` v26.6.7:

```
OwnNamespace=True  SingleNamespace=True  MultiNamespace=False  AllNamespaces=False
```

AllNamespaces is **not** supported, so this policy sets `targetNamespaces`. Without it the shared
chart's default produces a cluster-scoped OperatorGroup that OLM rejects, and the CSV sits in
`Failed` with `UnsupportedOperatorGroup` while the policy reports only that the CSV was not found.
