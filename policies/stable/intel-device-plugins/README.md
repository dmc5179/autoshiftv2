# Intel Device Plugins Policy

Deploys the Intel Device Plugins operator and configures the SGX device plugin
for TDX attestation via ACM governance policies.

## Policies

| Policy | Purpose |
| ------ | ------- |
| `policy-intel-device-plugins-operator-install` | Installs the intel-device-plugins-operator from the certified operator catalog |
| `policy-intel-device-plugins-sgx-config` | Deploys SgxDevicePlugin CR on nodes with SGX capability; depends on operator-install |

## Cluster Labels

Enable on a managed cluster:

```yaml
autoshift.io/intel-device-plugins: 'true'
```

Optional overrides:

| Label | Default | Description |
| ----- | ------- | ----------- |
| `autoshift.io/intel-device-plugins-subscription-name` | `intel-device-plugins-operator` | OLM subscription name |
| `autoshift.io/intel-device-plugins-channel` | `stable` | OLM channel |
| `autoshift.io/intel-device-plugins-source` | `certified-operators` | CatalogSource name |
| `autoshift.io/intel-device-plugins-source-namespace` | `openshift-marketplace` | CatalogSource namespace |
| `autoshift.io/intel-device-plugins-version` | *(latest)* | Pin to a specific CSV version |
| `autoshift.io/disconnected-mirror` | `false` | Appends mirror catalog suffix to source |

## SGX Device Plugin

The SgxDevicePlugin CR deploys a DaemonSet on nodes labeled
`intel.feature.node.kubernetes.io/sgx: 'true'` (set by NFD). It exposes SGX
resources (`sgx.intel.com/epc`, `sgx.intel.com/enclave`, `sgx.intel.com/provision`)
that the QGS DaemonSet requires for quote generation.

## Dependencies

- Node Feature Discovery operator (provides the `intel.feature.node.kubernetes.io/sgx` label)

## References

- [Intel Device Plugins for Kubernetes](https://github.com/intel/intel-device-plugins-for-kubernetes)
