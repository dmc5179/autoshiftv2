# osc

Installs the OpenShift sandboxed containers Operator, which runs pods inside lightweight virtual
machines through Kata Containers. For OpenShell it is an optional second isolation layer, at the
virtual machine level, underneath OpenShell's own kernel-enforced isolation. Agent Sandbox does not
need it.

This policy installs the Operator only. It creates no `KataConfig`, so no node gets the Kata
runtime until you create one. See [agent-sandbox](../agent-sandbox/README.md) for how the OpenShell
operator policies fit together.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-osc-operator-install` | enforce | The `openshift-sandboxed-containers-operator` namespace, an OwnNamespace OperatorGroup and the `sandboxed-containers-operator` subscription |

`osc` abbreviates the policy name to stay within the 40-character limit.

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      osc: 'true'
      osc-subscription-name: sandboxed-containers-operator
      osc-channel: stable
      osc-source: redhat-operators
      osc-source-namespace: openshift-marketplace
      # osc-version: 'sandboxed-containers-operator.v1.13.1'   # optional CSV pin
```

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

## Two steps this policy cannot do

1. The default Kata guest image ships **without the `nf_tables` kernel modules**, which OpenShell's
   sidecar needs to intercept traffic inside the guest. Sandbox creation fails without them. The
   modules have to be added separately, **and the change is lost on every worker reboot**. A
   MachineConfig would make it durable; none is written yet.
2. On bare metal, the ServiceAccount that applies that change needs the `privileged` SCC.

## Install mode

Checked against the catalog on OpenShift 4.22, `sandboxed-containers-operator` v1.13.1:

```
OwnNamespace=True  SingleNamespace=True  MultiNamespace=False  AllNamespaces=False
```

AllNamespaces is not supported, so this policy sets
`targetNamespaces: [openshift-sandboxed-containers-operator]`. Without it, the shared
operator-install chart's default produces an OperatorGroup that OLM refuses, and the CSV sits in
`Failed` with `UnsupportedOperatorGroup`.

## Verifying

```bash
oc get csv -n openshift-sandboxed-containers-operator
oc get kataconfig
```
