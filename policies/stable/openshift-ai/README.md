# openshift-ai

Installs the Red Hat OpenShift AI Operator and creates the platform: the `DSCInitialization` and the
`DataScienceCluster` that choose which OpenShift AI components run. Two opt-in policies enable the
MCP and Agents catalogs in the AI hub.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-openshift-ai-operator-install` | enforce | The `redhat-ods-operator` namespace and the `rhods-operator` subscription |
| `policy-openshift-ai-dsc` | enforce | `DSCInitialization` `default-dsci` and `DataScienceCluster` `default-dsc`. Waits for the Operator |
| `policy-openshift-ai-ready` | inform | The `DataScienceCluster` reports `Ready` |
| `policy-openshift-ai-mcp-catalog` | enforce | The `mcplifecycleoperator` component and the dashboard `mcpCatalog` flag. Opt-in |
| `policy-openshift-ai-genai-studio` | enforce | The dashboard `genAiStudio` flag: Gen AI studio AI asset endpoints and Playground (Technology Preview). Opt-in |
| `policy-openshift-ai-agents-cat` | enforce | The dashboard `agentsCatalog` flag. Opt-in |

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      openshift-ai: 'true'
      openshift-ai-subscription-name: rhods-operator
      openshift-ai-channel: stable-3.x
      openshift-ai-source: redhat-operators
      openshift-ai-source-namespace: openshift-marketplace
      # openshift-ai-version: 'rhods-operator.3.5.2'   # optional CSV pin
      openshift-ai-mcp-catalog: 'false'
      openshift-ai-agents-catalog: 'false'
      openshift-ai-genai-studio: 'false'
```

| Label | Meaning |
|---|---|
| `openshift-ai` and the standard operator labels | Install the Operator and create the platform |
| `openshift-ai-mcp-catalog` | Enable the MCP catalog. Technology Preview; needs OpenShift 4.22 or later and the MCP Gateway, which Red Hat Connectivity Link 1.5 includes |
| `openshift-ai-agents-catalog` | Enable the Agents catalog. Developer Preview |
| `openshift-ai-genai-studio` | Enable Gen AI studio: AI asset endpoints and Playground. Technology Preview; the Playground also needs the `ogx` component |

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

## The DataScienceCluster

The base component set is in `manifests/dsc/datasciencecluster.yaml`: every component `Managed`
except `kueue` and `trainer`, which need Operators this policy does not install, and the deprecated
`llamastackoperator`. Two settings in it are not obvious from the CRD.

**`llamastackoperator` must be `Removed`.** It is deprecated in favor of `ogx`. Leaving it
`Managed`, or unset on an existing `DataScienceCluster`, where it defaults to `Managed`, makes the
Operator reject `ogx`. That rejection aborts the whole module-provisioning batch, which stops
`aigateway` from installing its CRDs. The symptom is that Models-as-a-Service never appears while
`modelsAsAService` still reads `Managed`.

**`aigateway.modelsAsAService` is left out on purpose.** This policy enables `aigateway` but not
Models-as-a-Service. The [openshift-ai-maas](../openshift-ai-maas/README.md) policy sets
`modelsAsAService` to `Managed` on this same `DataScienceCluster`, together with the Gateway it
attaches to. Both policies use `musthave`, which merges only the fields each one lists, so neither
overwrites the other. Turning the `openshift-ai-maas` label off stops that policy managing the field
and removes nothing, like most AutoShift labels.

The `DSCInitialization` sets monitoring to `Managed` and deliberately leaves out the metrics and
traces configuration. Populating it starts the Operator's observability stack (MonitoringStack,
ThanosQuerier, Perses, tracing), which needs the Tempo, OpenTelemetry and Cluster Observability
Operators installed first. AutoShift has policies for all three. Enable those, then add the
configuration.

## Configuration

The `DataScienceCluster` and `DSCInitialization` specs are read from `config.openshift-ai`, the same
key the version pin uses, and merged over the base. Maps merge key by key, the configured value wins,
and a field removed from config returns to the base.

```yaml
hubClusterSets:
  hub:
    config:
      openshift-ai:
        dataScienceCluster:
          components:
            kueue:
              managementState: Managed     # once the Red Hat build of Kueue is installed
            trustyai:
              managementState: Removed
        dscInitialization:
          trustedCABundle:
            customCABundle: |
              -----BEGIN CERTIFICATE-----
              ...
```

Two fields cannot be set this way, for the reasons in the previous section: `llamastackoperator`
stays `Removed`, and `aigateway.modelsAsAService` is left to the openshift-ai-maas policy. A
configured value for either is dropped.

## The catalogs

Both catalogs configure objects this policy already owns, so they are extra policies on the same
objects rather than separate directories. `musthave` merges only the listed fields, so a partial
`DataScienceCluster` and a partial `OdhDashboardConfig` coexist with the main manifests.

- **MCP catalog.** The `mcplifecycleoperator` component and the dashboard flag ship together,
  because either alone is broken: the component without the flag is invisible, and the flag without
  the component gives a catalog whose Deploy action does nothing. The MCP Gateway is a prerequisite
  that OpenShift AI does not install. Red Hat Connectivity Link 1.5 includes it, so enable the
  [connectivity-link](../connectivity-link/README.md) policy on a 1.5 channel such as `stable-1.5`.
  No separate MCP Gateway Operator is installed.
- **Agents catalog.** A dashboard flag only. It has no component and no custom-source mechanism.

The model catalog needs nothing here: the main `DataScienceCluster` already enables what it needs.
Add custom model catalog sources in the dashboard. The Operator owns the sources ConfigMap, so a
policy managing it would fight the Operator.

## Dependencies

`policy-openshift-ai-dsc` depends on the Operator install, because both CRDs arrive with the CSV and
a `ConfigurationPolicy` naming an unknown kind reports Compliant while doing nothing. The catalogs
depend on `policy-openshift-ai-dsc`, and so does `policy-openshift-ai-maas-dsc` in openshift-ai-maas,
so that none of them creates a partial `default-dsc` before this policy creates the full one.

The OpenShift AI Operator requires cert-manager, from the [cert-manager](../cert-manager/README.md)
policy. Models-as-a-Service additionally needs [openshift-ai-maas](../openshift-ai-maas/README.md),
Red Hat Connectivity Link and LeaderWorkerSet.

## Disconnected

The `rhods-operator` bundle declares no OLM dependencies, so oc-mirror and the ImageSetConfiguration
generator only bring what the values enable or name. For an OpenShift AI mirror:

- cert-manager: `scripts/known-dependencies.json` maps `rhods-operator` to
  `openshift-cert-manager-operator`, so the generated ImageSetConfiguration includes it.
- Models-as-a-Service: Red Hat Connectivity Link and LeaderWorkerSet come from their own policies'
  labels, so enable those policies in the values the mirror is built from.
- Gateway API: the cluster ingress operator installs OpenShift Service Mesh 3 at a pinned version
  for the gateways that the dashboard and Models-as-a-Service use. See the Disconnected section of
  [connectivity-link](../connectivity-link/README.md).
- Model images, such as ModelCar OCI images, are in no operator catalog. Mirror them yourself.

## Verifying

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.aigateway}{"\n"}'
oc get csv -n redhat-ods-operator
```
