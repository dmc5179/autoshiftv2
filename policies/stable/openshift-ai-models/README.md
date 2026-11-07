# openshift-ai-models

Serves models through Red Hat OpenShift AI Models-as-a-Service (MaaS): an `LLMInferenceService`
per model, plus the MaaS records that say who may call it and how fast.

Enabled by the `autoshift.io/openshift-ai-models` label. **What** it serves comes from
`config.openshiftAiModels` in the cluster's rendered-config, not from labels. A model is a
structured record (URI, image, resources, rate limit), and a label is a string.

## Configuration

```yaml
config:
  openshiftAiModels:
    namespace: 'llm'                         # required: where the LLMInferenceServices live
    maasNamespace: 'models-as-a-service'
    gateway:
      name: 'maas-default-gateway'
      namespace: 'openshift-ingress'
    models:
      - name: 'granite-4-tiny-gpu'
        displayName: 'RedHatAI Granite 4.0-h-tiny FP8'
        uri: 'oci://registry.redhat.io/rhai/modelcar-granite-4-0-h-tiny-fp8-dynamic:3.0'
        image: 'registry.redhat.io/rhaii/vllm-cuda-rhel9@sha256:<digest>'
        replicas: 1
        gpus: 1
        requestsCpu: '2'
        requestsMemory: '8Gi'
        limitsCpu: '4'
        limitsMemory: '24Gi'
        accessGroups:
          - 'system:authenticated'
        tokenRateLimit: 50000
        tokenRateWindow: '1m'
        toolCallParser: 'granite4'
```

Every value in the sample is an example. The namespace, model, runtime image, groups and rate limit
are choices for your cluster, not recommendations.

| Field | Default | Notes |
|-------|---------|-------|
| `namespace` | | Required. Created by the policy and labeled for the MaaS gateway |
| `maasNamespace` | `models-as-a-service` | Where the MaaS subscription and auth policy live |
| `gateway.name` / `gateway.namespace` | `maas-default-gateway` / `openshift-ingress` | The Gateway `openshift-ai-maas` creates |
| `models` | | Required, at least one |
| `models[].name` | | Required. Resource name, and the served model name unless overridden |
| `models[].uri` | | Required. OCI modelcar or `hf://` |
| `models[].image` | | Required. vLLM runtime image. Pin it by digest; take the digest from the OpenShift AI CSV so a disconnected mirror already carries it |
| `models[].servedModelName` | `name` | See the warning below |
| `models[].displayName` | `name` | Dashboard label |
| `models[].replicas` | `1` | |
| `models[].gpus` | `1` | Both request and limit |
| `models[].requestsCpu` / `requestsMemory` | `2` / `8Gi` | |
| `models[].limitsCpu` / `limitsMemory` | `4` / `24Gi` | |
| `models[].accessGroups` | `[system:authenticated]` | Groups allowed to mint keys for the model and use its quota. The default includes every ServiceAccount on the cluster, so narrow it |
| `models[].tokenRateLimit` / `tokenRateWindow` | `50000` / `1m` | An agent framework sends its tool definitions on every turn, so a small window is exhausted by one prompt |
| `models[].priority` | `10` | Subscription priority |
| `models[].toolCallParser` | | Turns on tool calling. Model-specific: `granite4` for Granite 4.0-h, `hermes` for Qwen3, `openai` for gpt-oss, `llama3_json` for Llama 3.1 |
| `models[].chatTemplate` | | Needed with `llama3_json` |

The policy fails, and names the missing field, when `namespace` or `models` is missing, or when a
model has no `name`, `uri` or `image`. It also fails when the cluster's rendered-config ConfigMap
is missing. A placed policy with no models would otherwise report Compliant while serving nothing.

The vLLM entrypoint, TLS flags, probe timings and shared-memory volume are deliberately not
configurable. They are identical for every vLLM CUDA model, and exposing them would mean every
model entry repeated eighty lines to change a URI.

Without `toolCallParser`, a client that offers tools never gets a tool call back. That looks like
the model declining to use tools rather than a missing runtime flag.

## `servedModelName` is the one to be careful with

It is what callers put in the `model` field of an OpenAI-compatible request, and it is **not**
required to equal `metadata.name`. It defaults to `name` here, which is almost always what you
want.

If the two disagree, every policy reports Compliant, the pod is Ready, the route answers, and
inference returns:

```
404  The model <name> does not exist
```

The failure surfaces only at the first real request, which is the worst possible time. Set it
explicitly only when you mean to.

## Policies

| Policy | Mode | Does |
|--------|------|------|
| `policy-openshift-ai-models` | enforce | Namespace + an `LLMInferenceService` per model |
| `policy-openshift-ai-models-maas` | enforce | `MaaSModelRef`, `MaaSAuthPolicy`, `MaaSSubscription` per model |
| `policy-openshift-ai-models-ready` | inform | Each model's `Ready` condition, and that its `MaaSModelRef` exists |

Serving and MaaS registration are separate policies because the MaaS CRDs belong to a different
operator and appear later than KServe's. A `ConfigurationPolicy` naming a CRD that does not exist
yet reports Compliant while doing nothing, so the dependency chain is what makes the registration
assertion mean anything.

## Requirements

- [openshift-ai](../openshift-ai/README.md) and [openshift-ai-maas](../openshift-ai-maas/README.md),
  for the `DataScienceCluster` and the MaaS gateway. `policy-openshift-ai-models` depends on
  `policy-openshift-ai-maas`.
- A GPU node with the driver stack, for GPU models: `gpu-nodes` plus the NVIDIA GPU Operator.
  The pod tolerates the valueless `nvidia.com/gpu:NoSchedule` taint `gpu-nodes` applies.

A model pinned to a GPU it cannot get stays Pending indefinitely; `policy-openshift-ai-models-ready`
is what surfaces that.
