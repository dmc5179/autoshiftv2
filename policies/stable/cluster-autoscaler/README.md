# Cluster autoscaler

Turns on the OpenShift cluster autoscaler: one `ClusterAutoscaler` named `default`, with hard
resource limits, and a `MachineAutoscaler` for each compute machine set of the classes a
cluster opts into. Pods that cannot be scheduled then add nodes, up to the limits, and nodes
that stay underused are removed again.

## Policies

| Policy | Type | What it does |
|---|---|---|
| `policy-cluster-autoscaler` | enforce | The `ClusterAutoscaler` and the `MachineAutoscaler` objects |
| `policy-cluster-autoscaler-ready` | inform | The `cluster-autoscaler-default` Deployment in `openshift-machine-api` is available |

## Labels

| Label | Values | Meaning |
|---|---|---|
| `autoshift.io/cluster-autoscaler` | `'true'` / `'false'` | Enable the policies |

## Configuration

`config.clusterAutoscaler` in the values:

| Key | Required | Meaning |
|---|---|---|
| `resourceLimits` | yes | Copied into the `ClusterAutoscaler`: `maxNodesTotal`, `cores` and `memory` (GiB) `min`/`max`, optional `gpus` list of `{type, min, max}`. These are totals for the **whole** cluster, control plane included |
| `scaleDown` | no | Merged over `enabled: true`, `delayAfterAdd: 10m`, `unneededTime: 10m`, `utilizationThreshold: "0.5"` |
| `podPriorityThreshold` | no | Default `-10`. Pods below it never cause a scale-up |
| `machineSets.<class>` | no | `{minReplicas, maxReplicas}` for each machine set of that class. A class with no entry gets no `MachineAutoscaler` |

`resourceLimits.maxNodesTotal` is required on purpose: the policy refuses to turn on autoscaling
without a ceiling on how far it can scale.

The `cores` and `memory` minimums matter for scale-down. The autoscaler never removes a node if
doing so would take the cluster below them, so set them below what the smallest cluster you
want would have, not at its current size (Red Hat solution 6573321).

### Machine set classes

Machine sets are classified on the managed cluster, in this order:

1. **storage**: the template's node labels carry `cluster.ocs.openshift.io/openshift-storage`.
   Never autoscaled.
2. **gpu**: the template's node labels carry `node-role.kubernetes.io/gpu` or
   `cluster-api/accelerator`. Checked before the role, because a GPU machine set usually has the
   `worker` role too, and would otherwise scale with the workers.
3. **infra**: machine role `infra`.
4. **worker**: machine role `worker`.

The `minReplicas`/`maxReplicas` range applies to **each** machine set of the class. A cluster
with one worker machine set per zone and `minReplicas: 3` keeps at least three workers in every
zone.

A machine set must have at least one machine when its `MachineAutoscaler` is first created.

### GPU machine sets

Autoscaling a GPU machine set needs two things from whatever creates it:

- a `cluster-api/accelerator` node label in the machine set template, whose value matches a
  `resourceLimits.gpus[].type` entry, for example `nvidia-l4` for an AWS `g6` instance;
- not enforcing `spec.replicas`. A policy that sets the replica count and a `MachineAutoscaler`
  that changes it fight each other, and the replica count flaps.

Leave `machineSets.gpu` out until both hold.

## Example

```yaml
config:
  clusterAutoscaler:
    resourceLimits:
      maxNodesTotal: 12
      cores: {min: 8, max: 128}
      memory: {min: 4, max: 512}
    machineSets:
      worker:
        minReplicas: 3
        maxReplicas: 6
labels:
  cluster-autoscaler: 'true'
```

## Turning it off

`pruneObjectBehavior: None`: setting the label to `'false'` stops reconciliation and leaves the
`ClusterAutoscaler` and `MachineAutoscaler` objects in place, so nodes keep scaling. To stop
autoscaling, delete them:

```bash
oc delete machineautoscalers.autoscaling.openshift.io --all -n openshift-machine-api
oc delete clusterautoscalers.autoscaling.openshift.io default
```

## References

- OpenShift Container Platform 4.22, *Machine management*, chapter 7, "Applying autoscaling to a
  cluster": the `ClusterAutoscaler` and `MachineAutoscaler` resource definitions, and
  "Label GPU machine sets for the cluster autoscaler".
