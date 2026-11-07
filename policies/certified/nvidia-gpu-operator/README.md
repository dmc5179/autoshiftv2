# nvidia-gpu-operator

Installs the NVIDIA GPU Operator from the certified catalog and creates its `ClusterPolicy`, which
builds and loads the driver and makes each GPU node advertise `nvidia.com/gpu` capacity. The
directory is under `policies/certified/` because the Operator ships in `certified-operators`.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-nvidia-gpu-operator-install` | enforce | The `nvidia-gpu-operator` namespace, an OwnNamespace OperatorGroup and the `gpu-operator-certified` subscription |
| `policy-nvidia-gpu-cluster-policy` | enforce | `ClusterPolicy` `gpu-cluster-policy`: driver, container toolkit, device plugin, DCGM, GPU feature discovery. Waits for the Operator |
| `policy-nvidia-gpu-ready` | inform | The `ClusterPolicy` reports `Ready` |

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      node-feature-discovery: 'true'
      nvidia-gpu-operator: 'true'
      nvidia-gpu-operator-subscription-name: gpu-operator-certified
      nvidia-gpu-operator-channel: v25.3
      nvidia-gpu-operator-source: certified-operators
      nvidia-gpu-operator-source-namespace: openshift-marketplace
      # nvidia-gpu-operator-version: 'gpu-operator-certified.v25.3.4'   # optional CSV pin
```

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

## Requires Node Feature Discovery

The Operator selects GPU nodes by the Node Feature Discovery label
`feature.node.kubernetes.io/pci-10de.present=true`. The
[node-feature-discovery](../../stable/node-feature-discovery/README.md) policy produces it with its
default configuration, which labels PCI devices by vendor. Enable both. A `workerConfig` override in
`config.nodeFeatureDiscovery` that drops `deviceLabelFields: [vendor]` leaves the Operator with no
nodes to manage and no error.

## The ClusterPolicy matches the channel

The API server rejects the whole `ClusterPolicy` on the first field its CRD does not define, with
`strict decoding error: unknown field "spec.<x>"`. The policy then reports the resource as
"missing, and cannot be created", which reads like a permissions or ordering problem rather than a
schema mismatch. Every field in `manifests/cluster-policy/cluster-policy.yaml` exists in the CRD that
the default channel, `v25.3`, installs. Five fields from newer releases are left out for that reason:
`spec.cdi.nriPluginEnabled`, `spec.sandboxWorkloads.mode`, `spec.driver.licensingConfig.secretName`,
`spec.mps` and `spec.kataSandboxDevicePlugin`.

**When you change the channel, check the manifest against the new CRD**, for example with a
server-side dry run:

```bash
oc apply --dry-run=server -f <rendered ClusterPolicy>
```

`operator.use_ocp_driver_toolkit: true` builds the driver against the running Red Hat Enterprise
Linux CoreOS release rather than a pinned kernel, which is what lets it survive cluster upgrades.

## Install mode

The Operator's CSV declares `OwnNamespace=True`, `SingleNamespace=True` and `AllNamespaces=False`.
The shared operator-install chart defaults to an AllNamespaces OperatorGroup, which OLM refuses:

```
UnsupportedOperatorGroup: AllNamespaces InstallModeType not supported,
cannot configure to watch all namespaces
```

The CSV then never leaves `Failed`, while the policy reports only that the CSV was not found. This
policy sets `targetNamespaces: [nvidia-gpu-operator]`.

## A GPU node without a driver looks healthy

Until the driver stack finishes, which takes about 15 minutes on a new node, the node is `Ready` and
schedulable and reports no `nvidia.com/gpu` capacity, so GPU workloads stay `Pending` with no
obvious cause. `policy-nvidia-gpu-ready` asserts the `ClusterPolicy` `Ready` condition, which spans
the whole stack and names the component that is stuck.

GPU nodes themselves come from the cluster. On AWS, the [gpu-nodes](../../stable/gpu-nodes/README.md)
policy creates GPU MachineSets.

## Verifying

```bash
oc get csv -n nvidia-gpu-operator
oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}{"\n"}'
oc get pods -n nvidia-gpu-operator
oc get nodes -L feature.node.kubernetes.io/pci-10de.present
```
