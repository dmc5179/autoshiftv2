# Intel TDX DCAP Policy

Deploys the Intel TDX DCAP operator and configures QGS (Quote Generation
Service) on TDX-capable nodes via ACM governance policies.

## Policies

| Policy | Purpose |
| ------ | ------- |
| `policy-intel-tdx-dcap-operator-install` | Installs the intel-tdx-dcap-operator from the certified operator catalog |
| `policy-intel-tdx-dcap-qgs-config` | Deploys QgsConfig CR to run QGS on TDX nodes; depends on operator-install |

## Cluster Labels

Enable on a managed cluster:

```yaml
autoshift.io/intel-tdx-dcap: 'true'
```

Optional overrides:

| Label | Default | Description |
| ----- | ------- | ----------- |
| `autoshift.io/intel-tdx-dcap-subscription-name` | `intel-tdx-dcap-operator` | OLM subscription name |
| `autoshift.io/intel-tdx-dcap-channel` | `alpha` | OLM channel |
| `autoshift.io/intel-tdx-dcap-source` | `certified-operators` | CatalogSource name |
| `autoshift.io/intel-tdx-dcap-source-namespace` | `openshift-marketplace` | CatalogSource namespace |
| `autoshift.io/intel-tdx-dcap-version` | *(latest)* | Pin to a specific CSV version |
| `autoshift.io/disconnected-mirror` | `false` | Appends mirror catalog suffix to source |

## QGS Configuration

The QgsConfig CR tells the DCAP operator to deploy the QGS DaemonSet on nodes
labeled `intel.feature.node.kubernetes.io/tdx: 'true'` (set by NFD). QGS
provides the Quote Generation Service that TDX guests use to generate
attestation quotes.

### Note on Channel

The Intel TDX DCAP operator is currently in the `alpha` channel. The API version
and CR schema may change as the operator matures. Verify the CRD after
installation and adjust `qgs-config.yaml` if the schema has changed.

## Dependencies

- Node Feature Discovery operator (provides `intel.feature.node.kubernetes.io/tdx` label)
- Intel Device Plugins operator (provides SGX device resources that QGS requires)
- PCCS must be reachable from TDX nodes (deployed separately, see
  `intel-tdx-remote-attestation-disconnected/`)

## References

- [Intel TDX DCAP operator on OperatorHub](https://catalog.redhat.com/software/container-stacks/detail/66fbb1a6e39f3965d494aa3f)
