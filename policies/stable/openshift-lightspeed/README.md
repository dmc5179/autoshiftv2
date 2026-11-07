# openshift-lightspeed

Installs the Red Hat OpenShift Lightspeed Operator and points the console assistant at a model served
through Models-as-a-Service (MaaS) on the same cluster, so cluster questions are answered by your
own model rather than by a SaaS provider.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-ols-operator-install` | enforce | The `openshift-lightspeed` namespace, an OwnNamespace OperatorGroup and the `lightspeed-operator` subscription |
| `policy-ols-config` | enforce | The `OLSConfig` named `cluster`, with one `rhoai_vllm` provider at the MaaS gateway |
| `policy-ols-ready` | inform | The `lightspeed-app-server` Deployment is `Available` |

`ols` abbreviates the policy names to stay within the 40-character limit.

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      openshift-lightspeed: 'true'
      openshift-lightspeed-subscription-name: 'lightspeed-operator'
      openshift-lightspeed-channel: 'stable'
      openshift-lightspeed-source: 'redhat-operators'
      openshift-lightspeed-source-namespace: 'openshift-marketplace'
      # openshift-lightspeed-version: 'lightspeed-operator.v1.1.5'   # optional CSV pin
    config:
      openshiftLightspeed:
        model: 'publishers/llm/models/granite-4-tiny-gpu'
        secretName: 'maas-api-key'
```

| Key | Default | Notes |
|---|---|---|
| `config.openshiftLightspeed.model` | | Required. A model id the MaaS gateway lists |
| `config.openshiftLightspeed.secretName` | `maas-api-key` | Secret in `openshift-lightspeed` holding the API key |

The model in the sample is an example. MaaS lists models as `publishers/<namespace>/models/<name>`.
Find the id with a MaaS API key:

```bash
curl -sk -H "Authorization: Bearer $KEY" https://maas.<ingress domain>/maas-api/v1/models | jq -r '.data[].id'
```

The model is configuration rather than a label because a label value cannot contain a slash. It has
no default: a template cannot query the gateway's model listing, and a wrong id gives an assistant
that fails every question. The policy fails, and names the key, when the model is missing. It also
fails when the cluster's rendered-config ConfigMap is missing.

## The API key

The `OLSConfig` references a Secret by name. No policy creates it, because it holds a credential.
Mint a MaaS API key for a group the model's subscription admits, then:

```bash
oc create secret generic maas-api-key -n openshift-lightspeed \
  --from-literal=apitoken=<key>
```

The key inside the Secret is always `apitoken`, whatever the provider calls it. MaaS keys expire,
and Lightspeed has no rotation of its own. Mint the key with a long lifetime and create the Secret
again before it lapses.

## How the provider is built

- The URL is `https://maas.<ingress domain>/v1`, the hostname the
  [openshift-ai-maas](../openshift-ai-maas/README.md) Gateway listens on. Lightspeed requires the
  trailing `/v1`.
- The domain is discovered on the managed cluster from the cluster `Ingress` configuration, which is
  always populated. The default `IngressController` `spec.domain` is set only when someone configures
  it, and reading it renders `https://maas.%!s(<nil>)/v1`: a valid string, and an assistant that
  fails every request.
- The provider type is `rhoai_vllm`, the type for a self-hosted vLLM endpoint.

Serve the model with tool calling enabled, so the assistant can use its cluster tools. With
`openshift-ai-models`, set `toolCallParser` on the model.

## Install mode

`lightspeed-operator` v1.1.5 declares `OwnNamespace=True` and `AllNamespaces=False`. The shared
operator-install chart defaults to an AllNamespaces OperatorGroup, which OLM refuses: the CSV sits in
`Failed` with `UnsupportedOperatorGroup` while the policy reports only that the CSV was not found.
This policy sets `targetNamespaces: [openshift-lightspeed]`.

## Dependencies

`policy-ols-config` depends on `policy-ols-operator-install`, because the `OLSConfig` CRD arrives
with the CSV, and on `policy-openshift-ai-maas`, because the provider is the MaaS gateway. A model
must be served behind that gateway, for example by
[openshift-ai-models](../openshift-ai-models/README.md).

## Verifying

```bash
oc get olsconfig cluster -o jsonpath='{.spec.llm.providers[0].url}{"\n"}{.spec.ols.defaultModel}{"\n"}'
oc get deployment lightspeed-app-server -n openshift-lightspeed
```
