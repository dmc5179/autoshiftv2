# openshift-ai-models

Serves models through RHOAI Models-as-a-Service: an `LLMInferenceService` per model, plus the
MaaS records that say who may call it and how fast.

Enabled by the `autoshift.io/openshift-ai-models` label. **What** it serves comes from
`config.openshiftAiModels` in the cluster's rendered-config, not from labels — a model is a
structured record (uri, image, resources, rate limit), and a label is a string.

## Configuration

```yaml
config:
  openshiftAiModels:
    namespace: 'llm'                         # where the LLMInferenceServices live
    maasNamespace: 'models-as-a-service'
    gateway:
      name: 'maas-default-gateway'
      namespace: 'openshift-ingress'
    models:
      - name: 'granite-4-tiny-gpu'
        displayName: 'RedHatAI Granite 4.0-h-tiny FP8'
        uri: 'oci://registry.redhat.io/rhai/modelcar-granite-4-0-h-tiny-fp8-dynamic:3.0'
        image: 'registry.redhat.io/rhaii/vllm-cuda-rhel9:3.0'
        replicas: 1
        gpus: 1
        requestsCpu: '2'
        requestsMemory: '8Gi'
        limitsCpu: '4'
        limitsMemory: '24Gi'
        tokenRateLimit: 100
        tokenRateWindow: '1m'
```

| Field | Default | Notes |
|-------|---------|-------|
| `name` | — | Resource name, and the served model name unless overridden |
| `servedModelName` | `name` | See the warning below |
| `uri` | — | OCI modelcar or `hf://` |
| `image` | — | vLLM runtime image |
| `displayName` | `name` | Dashboard label |
| `replicas` | `1` | |
| `gpus` | `1` | Both request and limit |
| `requestsCpu` / `requestsMemory` | `2` / `8Gi` | |
| `limitsCpu` / `limitsMemory` | `4` / `24Gi` | |
| `accessGroup` | `system:authenticated` | Who may call the model |
| `tokenRateLimit` / `tokenRateWindow` | `100` / `1m` | |
| `priority` | `10` | Subscription priority |

The vLLM entrypoint, TLS flags, probe timings and shared-memory volume are deliberately not
configurable — they are identical for every vLLM CUDA model, and exposing them would mean every
model entry repeated eighty lines in order to change a URI.

## `servedModelName` is the one to be careful with

It is what callers put in the `model` field of an OpenAI-compatible request, and it is **not**
required to equal `metadata.name`. It defaults to `name` here, which is almost always what you
want.

If the two disagree, every policy reports Compliant, the pod is Ready, the route answers — and
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

- `openshift-ai` and `openshift-ai-maas` — the DataScienceCluster and the MaaS gateway
- A GPU node with the driver stack, for GPU models: `gpu-nodes` plus `nvidia-gpu-operator`.
  The pod tolerates the valueless `nvidia.com/gpu:NoSchedule` taint `gpu-nodes` applies.

A model pinned to a GPU it cannot get stays Pending indefinitely; `policy-openshift-ai-models-ready`
is what surfaces that.
