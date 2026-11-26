# openshift-gitops (policy)

**This policy is a plain Helm chart, not a PolicyGenerator policy — on purpose.**

Every other policy under `policies/` is rendered by PolicyGenerator: a `policy-generator-config.yaml`
is discovered by the ArgoCD **PolicyGenerator ConfigManagementPlugin (CMP)** sidecar, which runs
`kustomize` + PolicyGenerator to wrap plain manifests into ACM `Policy` objects. `openshift-gitops`
**cannot** work that way, because it is the chart that *creates that machinery in the first place*.

## Why not PolicyGenerator

`openshift-gitops` bootstraps the two things PolicyGenerator depends on:

1. **OpenShift GitOps (ArgoCD) itself** — the engine that runs every AutoShift ArgoCD Application,
   including the ApplicationSet that deploys all the other `policies/*`.
2. **The PolicyGenerator CMP** — `templates/policy-gitops-cmp-plugin.yaml` places the
   `ConfigManagementPlugin` named `policy-generator` onto every hub (plus its sidecar wiring on the
   ArgoCD CR through `policy-gitops-systems-argocd.yaml`). Until this exists, no
   `policy-generator-config.yaml` anywhere in the repo can be rendered.

   It ships as a `Policy` rather than a ConfigMap that ArgoCD applies, for two reasons. A managed
   hub never runs the bootstrap chart and never syncs this chart in-cluster, so ArgoCD cannot reach
   it. And on any hub, an ArgoCD copy cannot heal a missing ConfigMap: the repo-server fails to
   mount it and stops, and ArgoCD needs that repo-server to render this chart. The
   `config-policy-controller` carries the desired ConfigMap inside the `Policy` itself, so it
   restores it with ArgoCD still down.

That is a chicken-and-egg: PolicyGenerator cannot render the chart whose job is to install
PolicyGenerator. So this chart emits its `Policy` objects **directly as Helm templates**.

It is also installed by `helm install` during **bootstrap phase 1**, before ArgoCD (and therefore the
CMP) exist at all — another reason it must stand alone as a Helm chart.

## Dual role (bootstrap + day-2)

- **Day-0 bootstrap:** the root-level `openshift-gitops/` chart is `helm install`-ed to stand up ArgoCD
  and ship a day-0 copy of the CMP config.
- **Day-2 self-heal:** this `policies/stable/openshift-gitops/` chart is deployed as a self-healing
  ArgoCD Application that continuously reconciles the GitOps configuration — the operator install, the
  ArgoCD instances, the PolicyGenerator CMP, the user CA bundle, and the console link.

## Consequences for authors

Because the `Policy` objects here are hand-written Helm templates (not PolicyGenerator output):

- **Hub templates must be Helm-escaped**: write `{{ "{{hub" }} … {{ "hub}}" }}` (and `{{ "{{hub-" }}`
  for the trim form), because Helm renders the file before ACM ever sees it. Contrast the raw
  `{{hub … hub}}` you can write in a PolicyGenerator manifest.
- **The operator install is hand-written too** (`policy-gitops-operator-install.yaml`), not the shared
  `components/operator-install` chart — the whole `OperatorPolicy` lives inline in a Helm template.
- Placements, `PlacementBinding`s, and `remediationAction` are authored by hand here, not generated.

Version pinning still behaves like every other operator: set `config.gitops.versions` (and optional
`config.gitops.startingCSV`), else the `autoshift.io/gitops-version` label is used — implemented inline
in `policy-gitops-operator-install.yaml`.

## Argo CD agent

`policy-gitops-operator-install.yaml` adds each principal namespace, for infra and for each team, to
`ARGOCD_CLUSTER_CONFIG_NAMESPACES`, because OpenShift GitOps reconciles `sourceNamespaces` only for
a cluster-scoped instance. Comments belong **above** that env key, never inside its value: it is a
folded scalar, hub templates have no comment syntax, and a `#` line there is folded into the value.

See [Argo CD agent](../../../docs/gitops-agent.md) for the user-facing guide and
[gitops-dev](../gitops-dev/README.md) for the per-team agents.

## Sign-in through an OIDC provider

Set `config.gitops.sso.mode: 'oidc'` to sign users in through the cluster's OIDC provider (Keycloak)
instead of Dex. A cluster on external OIDC authentication has no OAuth server, which is what
Dex's OpenShift connector talks to, and from OpenShift GitOps 1.20 the operator does not deploy Dex
there at all. `spec.sso` and `spec.oidcConfig` are mutually exclusive in the ArgoCD CR, so the oidc
mode drops the Dex stanza entirely and writes `spec.oidcConfig` from the block below.

| Key | Notes |
|---|---|
| `mode` | `'oidc'` to switch; anything else renders today's Dex stanza |
| `issuer` | required with `clientID`; the provider's issuer URL |
| `clientID` | required with `issuer` |
| `clientSecretRef` | optional; where Argo CD reads the client secret, written as `$<clientSecretRef>`: a key in `argocd-secret` (default `oidc.clientSecret`), or `<secret>:<key>` for a separate Secret |
| `rootCA` | optional PEM of the CA signing the issuer's certificate, when not publicly trusted |
| `adminGroups` | optional list of identity-provider groups granted `role:admin` in `rbac.policy`, on top of `gitops.infra.rbac_policies` |

Mode `oidc` with a missing `issuer` or `clientID` fails the template render.

The Keycloak client is confidential: standard flow on, direct access grants off, and a redirect URI
of `https://<argocd route host>/auth/callback`. Request the `groups` scope so group names arrive in
the token's `groups` claim, which is what `rbac.scopes: '[groups]'` reads. The client secret value
never comes from values. The simplest home is a Secret of its own in the instance namespace,
labeled `app.kubernetes.io/part-of: argocd` so that Argo CD may read it, with
`clientSecretRef: '<secret>:<key>'`. The operator owns `argocd-secret`, so a key added there by hand
is not part of what it manages. Create the Secret without putting the value on a command line:

```bash
printf '%s' "$CLIENT_SECRET" | oc create secret generic argocd-oidc -n openshift-gitops \
  --from-file=clientSecret=/dev/stdin
oc label secret argocd-oidc -n openshift-gitops app.kubernetes.io/part-of=argocd
```

Keycloak rejects a scope it does not know, so the realm needs a `groups` client scope (with a group
membership mapper, full group path off) assigned to the client.

One risk to respect: never set `config.gitops.infra.disableAdmin` until SSO sign-in is proven in a
browser. The local admin account is the only way in when the issuer URL, the CA or the groups claim
is wrong, and the policy will keep reporting the ArgoCD CR applied either way.
