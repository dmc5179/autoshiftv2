# Sandboxed Containers Policy

Deploys the OpenShift Sandboxed Containers operator and configures Confidential
Containers (CoCo) runtime via ACM governance policies.

## Policies

| Policy | Purpose |
| ------ | ------- |
| `policy-sandboxed-containers-operator-install` | Installs the sandboxed-containers-operator via the shared `operator-install` chart |
| `policy-sandboxed-containers-coco-config` | Applies CoCo configuration (feature gates + KataConfig); depends on operator-install |

## Cluster Labels

Enable on a managed cluster:

```yaml
autoshift.io/sandboxed-containers: 'true'
```

Optional overrides:

| Label | Default | Description |
| ----- | ------- | ----------- |
| `autoshift.io/sandboxed-containers-subscription-name` | `sandboxed-containers-operator` | OLM subscription name |
| `autoshift.io/sandboxed-containers-channel` | `stable` | OLM channel |
| `autoshift.io/sandboxed-containers-source` | `redhat-operators` | CatalogSource name |
| `autoshift.io/sandboxed-containers-source-namespace` | `openshift-marketplace` | CatalogSource namespace |
| `autoshift.io/sandboxed-containers-version` | *(latest)* | Pin to a specific CSV version |
| `autoshift.io/sandboxed-containers-confidential` | `true` | Enable confidential containers feature gate |
| `autoshift.io/disconnected-mirror` | `false` | Appends mirror catalog suffix to source |

## CoCo Configuration

The `coco-config` manifests apply:

- **osc-feature-gates** ConfigMap — enables `confidential: "true"` and `deploymentMode: DaemonSetFallback`
- **KataConfig** CR — `enablePeerPods: false`, `checkNodeEligibility: true`

NodeFeatureRules for TDX/SNP/SGX detection and MachineConfig for kernel
arguments are managed by separate policies (NFD and infrastructure).

## Dependencies

This policy requires:

- Node Feature Discovery operator (for `checkNodeEligibility`)
- Intel Device Plugins operator (for TDX QGS and SGX plugin, if using Intel TDX)
- Trustee operator (for attestation and secret delivery)

## References

- [OpenShift Sandboxed Containers documentation](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers)
- [Confidential Containers on bare metal](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/1.8/html/deploying_openshift_sandboxed_containers_on_bare_metal)
