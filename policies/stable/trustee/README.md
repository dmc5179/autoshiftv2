# Trustee Policy

Deploys the Red Hat build of Trustee (Key Broker Service) operator and
configures KBS for confidential containers attestation via ACM governance
policies.

## Policies

| Policy | Purpose |
| ------ | ------- |
| `policy-trustee-operator-install` | Installs the trustee-operator via the shared `operator-install` chart |
| `policy-trustee-config` | Deploys KBS configuration (ConfigMap + KbsConfig CR); depends on operator-install |

## Cluster Labels

Enable on a managed cluster:

```yaml
autoshift.io/trustee: 'true'
```

Optional overrides:

| Label | Default | Description |
| ----- | ------- | ----------- |
| `autoshift.io/trustee-subscription-name` | `trustee-operator` | OLM subscription name |
| `autoshift.io/trustee-channel` | `stable` | OLM channel |
| `autoshift.io/trustee-source` | `redhat-operators` | CatalogSource name |
| `autoshift.io/trustee-source-namespace` | `openshift-marketplace` | CatalogSource namespace |
| `autoshift.io/trustee-version` | *(latest)* | Pin to a specific CSV version |
| `autoshift.io/disconnected-mirror` | `false` | Appends mirror catalog suffix to source |

## KBS Configuration

The `trustee-config` manifests deploy:

- **kbs-config-cm** ConfigMap — TOML configuration for KBS with built-in
  attestation service (CoCo AS), OPA policy engine, built-in RVPS, and
  local filesystem resource plugin
- **KbsConfig** CR — tells the trustee operator to deploy KBS using the
  ConfigMap and an auth secret for admin API access

### Post-Deployment Steps

After the policy deploys KBS, you must manually provision:

1. **Auth key pair** — create the `kbs-auth-public-key` Secret with an RSA
   public key for admin API authentication
2. **RVPS reference values** — populate reference values for your TEE platform
   (Intel TDX, AMD SEV-SNP) so attestation can validate guest measurements
3. **KBS repository secrets** — add secrets to the KBS repository that
   confidential workloads will retrieve after attestation

### FIPS Note

Trustee TLS certificate handling should use FIPS-validated algorithms.
Verify that the KBS TLS configuration uses RSA-2048+ or ECDSA with
NIST-approved curves when deploying in FIPS-enabled clusters.

## Dependencies

This policy should be deployed alongside:

- Sandboxed Containers operator (provides the CoCo runtime that calls KBS)
- Node Feature Discovery operator (detects TEE hardware capabilities)

## References

- [Red Hat build of Trustee documentation](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/1.8/html/deploying_openshift_sandboxed_containers_on_bare_metal/deploying-trustee)
- [Confidential Containers attestation](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers)
