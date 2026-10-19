# gitops-workloads

Deploy workloads that live in **their own repositories** as ArgoCD Applications,
rather than vendoring their manifests into this one.

AutoShift policies configure the platform: operators, DataScienceCluster
components, gateways, node pools. A tenant workload is a different thing — it
has its own repo, its own release cadence and its own team. Copying its
manifests under `policies/` turns this repository into a monorepo for software
that has nothing to do with it, with every workload's release landing as a merge
conflict here.

This policy creates the `Application` instead. The content stays where its
owners work; AutoShift decides only **whether a cluster gets it**.

The marginal cost of the next workload is a few lines in a values file, not a
directory here.

## When to use this, and when not to

| | |
|---|---|
| Operators, cluster config, node pools | a normal policy |
| A **shaped CR** that varies by a few fields | a config-driven policy, ranging over a list — see `openshift-ai-models` |
| **Arbitrary manifests** with their own repo and cadence | **this** |

If you can template the thing as a CR, do that instead: it stays in-repo at zero
marginal cost and you keep real compliance reporting on the object itself.

## Configuration

Enablement label `autoshift.io/gitops-workloads`, plus `config.gitopsWorkloads`
to say which workloads. The label alone deploys nothing.

```yaml
config:
  gitopsWorkloads:
    gitopsNamespace: openshift-gitops     # shared default; per-entry override allowed
    workloads:
      - name: hermes-agent
        repoUrl: https://github.com/example/hermes-openshift
        targetRevision: maas-gitops
        path: gitops/overlays/prod
        destinationNamespace: hermes
        createNamespace: false
        prune: true
        selfHeal: true
```

| Key | Default | Notes |
|---|---|---|
| `name` | — | **required**; also the `Application` name |
| `repoUrl` | — | **required** |
| `path` | — | **required**; the directory Argo renders |
| `destinationNamespace` | — | **required** |
| `targetRevision` | `main` | often wrong — a deployment tree frequently lives on its own branch |
| `createNamespace` | `true` | emitted explicitly either way as a `syncOption` |
| `prune` | `false` | |
| `selfHeal` | `true` | |
| `project` | `default` | |
| `destinationServer` | `https://kubernetes.default.svc` | |
| `gitopsNamespace` | `openshift-gitops` | where the `Application` object goes |
| `helm` | — | passed through verbatim |
| `ignoreDifferences` | — | passed through verbatim |
| `retry` | — | passed through verbatim |
| `syncOptions` | — | appended after the generated `CreateNamespace=` |

An entry missing any required field is **skipped entirely**. It is not
partially created: under `enforce`, an unguarded template produces an
`Application` pointing nowhere rather than no `Application` at all.

## What it creates

| | |
|---|---|
| `policy-gitops-workloads` | one `argoproj.io/v1alpha1` `Application` per configured workload |
| `policy-gitops-workloads-ready` | inform-only: each `Application` reports `health.status: Healthy` and `sync.status: Synced` |

## Why the readiness policy is not optional

A policy that creates an `Application` reports compliance on **the Application
object**. It goes Compliant the moment the CR matches what was asked for — while
the Application is `Degraded`, `OutOfSync`, stuck on a missing repo credential,
or pointed at a branch that does not exist. Same shape as a
`ConfigurationPolicy` naming a CRD that does not exist yet: what the policy was
told to do succeeded, and what you wanted did not happen.

`policy-gitops-workloads-ready` asserts both conditions, because they fail
independently. A typo in `path` shows as `OutOfSync`; a `CrashLoopBackOff` shows
as `Degraded`.

## AutoShift owns these Applications

`complianceType: mustonlyhave`. `syncOptions`, `ignoreDifferences` and the Helm
value lists are object **lists**, and `musthave` merges into a list rather than
replacing it — changing `targetRevision` under `musthave` would leave both
revisions in place while the policy reported Compliant. See
[policy-behavior.md](../../../docs/policy-behavior.md).

The consequence: **edit the values file, not the Application.** A hand-edit is
reverted on the next evaluation.

## Data safety

An `Application` that owns a `Namespace` and carries
`resources-finalizer.argocd.argoproj.io` **cascades on delete** — namespace,
then PVCs, then whatever the workload had stored. For a *generated* Application
that is sharper than for a hand-made one, because a values-file edit is enough
to stop an entry being emitted.

Two things make that safe:

- **`pruneObjectBehavior: None`** on this policy. Removing a workload from the
  list stops reconciling it and does **not** delete the `Application`. Deleting
  a workload is therefore a deliberate, manual act — the right way round for
  something holding state.
- **Renaming an entry creates a second `Application`**, it does not rename the
  first. The old one keeps running; tidy it by hand.

A workload with a PVC it cares about should also carry
`argocd.argoproj.io/sync-options: Prune=false` on that PVC **in its own repo**.
This policy cannot add it — the annotation belongs on the resource, which lives
in the other repository.

## What this does not do

- **Secrets.** A workload needing credentials gets them out of band, the same
  way the MaaS database URL and the Lightspeed API key do. Nothing here puts a
  credential in git.
- **Ordering against those secrets.** If a workload's pod cannot start without a
  Secret that a human must create, the `Application` will sit `Degraded` on a
  fresh cluster until someone creates it — and `policy-gitops-workloads-ready`
  will report exactly that, correctly, indefinitely. That is a true reading of
  the cluster, not a policy bug, but it means **a workload with a manual
  credential prerequisite is not fully push-button** and should say so in its
  own documentation.
- **Repo credentials.** A private `repoUrl` needs its repository registered with
  ArgoCD first.
