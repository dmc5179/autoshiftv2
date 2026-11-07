# agent-sandbox

Installs the Red Hat build of Agent Sandbox Operator, which serves the `sandboxes.agents.x-k8s.io`
API for running AI agents in isolated sandboxes. OpenShell, the agent runtime that ships as a
Developer Preview with Red Hat OpenShift AI 3.5, requires it.

This policy installs the Operator only. It creates no sandboxes, and OpenShell itself has no
policy: it is a Helm chart plus manifests with no OperatorHub entry, and is not supported for
production. The OLM operators it depends on are the part AutoShift and disconnected mirroring can
manage. The others are the optional [rhbk](../rhbk/README.md) and [osc](../osc/README.md) policies.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-agent-sandbox-operator-install` | enforce | The `agent-sandbox-system` namespace and the `agent-sandbox-operator` subscription |

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      agent-sandbox: 'true'
      agent-sandbox-subscription-name: agent-sandbox-operator
      agent-sandbox-channel: preview-0.9
      agent-sandbox-source: redhat-operators
      agent-sandbox-source-namespace: openshift-marketplace
      # agent-sandbox-version: 'agent-sandbox-operator.v0.9.0'   # optional CSV pin
```

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

## Requirements

- OpenShift 4.19 or later.
- Red Hat Enterprise Linux CoreOS worker nodes. RHEL worker nodes are not supported.

## Use this, not the upstream manifest

OpenShell's own disconnected guidance points at the upstream `kubernetes-sigs/agent-sandbox` release
manifest. This Operator is a catalog entry, so standard `oc-mirror` catalog mirroring carries it,
where the upstream manifest's image reference has to be rewritten by hand.

**Do not install both.** They ship the same CRDs into the same `agent-sandbox-system` namespace and
collide.

OpenShell's preflight checks for `sandboxes.agents.x-k8s.io` serving `v1beta1` and for an
`agent-sandbox-operator` CSV. This Operator satisfies both.

## Install mode

Checked against the catalog on OpenShift 4.22, `agent-sandbox-operator` v0.9.0:

```
OwnNamespace=False  SingleNamespace=False  MultiNamespace=False  AllNamespaces=True
```

AllNamespaces is the only mode the Operator supports, and it is what the shared operator-install
chart produces by default, so this policy sets no `targetNamespaces`.

## Verifying

```bash
oc get csv -n agent-sandbox-system
oc get crd sandboxes.agents.x-k8s.io -o jsonpath='{.spec.versions[*].name}{"\n"}'
```
