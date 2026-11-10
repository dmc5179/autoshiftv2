# openshift-lightspeed

Installs the Red Hat OpenShift Lightspeed Operator and points the console assistant at a model served
through Models-as-a-Service (MaaS) on the same cluster, so cluster questions are answered by your
own model rather than by a SaaS provider.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-ols-operator-install` | enforce | The `openshift-lightspeed` namespace, an OwnNamespace OperatorGroup and the `lightspeed-operator` subscription |
| `policy-ols-config` | enforce | The `OLSConfig` named `cluster`, with one `rhoai_vllm` provider at the MaaS gateway, and optionally more MCP servers, the tool-result inspection switch and the tool budget |
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
| `config.openshiftLightspeed.mcpServers` | | Optional. More MCP servers; see [MCP servers](#mcp-servers) |
| `config.openshiftLightspeed.toolResultInspection` | operator default, enabled | Optional, `true` or `false`; see [Tool-result inspection](#tool-result-inspection) |
| `config.openshiftLightspeed.toolBudgetRatio` | CRD default, `0.5` | Optional, `0.1` to `0.5`. The share of the model's context window for tool results |

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

## MCP servers

Lightspeed always has its built-in `openshift` MCP server. `mcpServers` adds more, which the
`OLSConfig` CRD supports as a Technology Preview behind the `MCPServer` feature gate; the policy
sets the gate whenever the list is not empty.

```yaml
config:
  openshiftLightspeed:
    mcpServers:
      - name: 'redhat-docs'
        ingressHost: 'mcp'            # https://mcp.<ingress domain>/mcp
        timeout: 60
        headers:
          - name: 'Authorization'
            valueFrom:
              type: 'kubernetes'      # the signed-in user's token
```

| Field | Default | Notes |
|---|---|---|
| `name` | | Required, unique. Not `openshift`, the built-in server's name |
| `url` | | A literal `http://` or `https://` URL. Exactly one of `url` and `ingressHost` |
| `ingressHost` | | A single DNS label. Renders `https://<ingressHost>.<ingress domain><path>`, with the domain read on the managed cluster, as the provider URL is |
| `path` | `/mcp` | With `ingressHost` only |
| `timeout` | `60` | Seconds. The CRD's own default is 5, shorter than a documentation search |
| `headers` | | Passed through. `valueFrom.type` is `secret` (with `secretRef.name`, a Secret in `openshift-lightspeed`), `kubernetes` (the user's token) or `client` |

With the [mcp-gateway](../mcp-gateway/README.md) policy, point one entry at the gateway with the
`kubernetes` header. The gateway authenticates each user's token and its tool access entries decide
which tools that user sees, so Lightspeed's list of servers does not change when servers are
added behind the gateway, or when their backend changes.

The gateway's public host is served with the default ingress certificate, the same one the MaaS
provider URL uses, so no extra CA is configured here.

`policy-ols-config` does not depend on the MCP servers it lists: the fields are generic, and a
server that is down costs only its tools. Enable the policy that provides a server together with
its entry here.

Removing an entry from `mcpServers` does not remove it from the `OLSConfig`, because `musthave`
never removes list entries. Remove it by hand:

```bash
oc get olsconfigs.ols.openshift.io cluster -o jsonpath='{range .spec.mcpServers[*]}{.name}{"\n"}{end}'
oc patch olsconfigs.ols.openshift.io cluster --type=json \
  -p '[{"op":"remove","path":"/spec/mcpServers/<index>"}]'
```

## Tool-result inspection

Lightspeed inspects each tool result before the model uses it, and stops the answer when a result
fails. `toolResultInspection: false` sets `spec.ols.guardrails.toolResultInspection.enabled: false`,
which is the documented workaround for the OpenShift Lightspeed 1.1.5 known issue "Tool-result
inspection might fail at the tool call step for certain models", and for OLS-4416, where
classifier errors were reported as unsafe results. Unset, the policy writes nothing and the
operator default applies, which is enabled.

It applies to every MCP server, the built-in `openshift` one included. Prefer smaller tool results
first (for `rhokp-mcp`, `config.rhokpMcp.maxResponseChars`), and record turning it off as a
deliberate choice. To turn it back on, set `true`: removing the key leaves the last value in the
`OLSConfig`.

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
oc get olsconfigs.ols.openshift.io cluster -o jsonpath='{.spec.llm.providers[0].url}{"\n"}{.spec.ols.defaultModel}{"\n"}'
oc get deployment lightspeed-app-server -n openshift-lightspeed
```
