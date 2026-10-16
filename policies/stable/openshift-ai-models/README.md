# openshift-ai-models AutoShift Policy

## Overview

Deploys large language models behind Models-as-a-Service, using AutoShift's ACM
**PolicyGenerator** pattern. Each model is an `LLMInferenceService` serving the weights, a
`MaaSModelRef` publishing it through the gateway, and `MaaSSubscription` resources defining the
access tiers consumers subscribe to.

The MaaS platform itself is [openshift-ai-maas](../openshift-ai-maas/README.md).

## Model weights

Models are pulled as OCI images (modelcars) from `registry.redhat.io` rather than downloaded at
runtime, which makes pulls repeatable, mirrorable, and viable disconnected. The cluster pull secret
must therefore cover `registry.redhat.io`.

## A trap worth knowing

vLLM is started with `--served-model-name` taken from the `LLMInferenceService` **metadata.name**,
while MaaS advertises and forwards `spec.model.name`. If those two disagree, every call fails:

```json
{"error":{"message":"The model `x` does not exist.","code":404}}
```

Routing, auth, and rate limiting all work, and the model listing is populated, so it reads as a
serving fault rather than a one-line mismatch. Keep the two names identical.

## GPU

GPU-backed models need a node advertising `nvidia.com/gpu` **before** the model is deployed, which
means [nvidia-gpu-operator](../../certified/nvidia-gpu-operator/README.md) and
[node-feature-discovery](../node-feature-discovery/README.md) must already be reconciled. Nodes are
conventionally tainted `nvidia.com/gpu:NoSchedule`; the model manifests carry the matching
toleration.

CPU-only models exist and need none of that.

## Labels

| Label | Meaning |
|---|---|
| `openshift-ai-models` | enable on this cluster |

Declared in `autoshift/values/clustersets/_example.yaml`. Which models to deploy is config rather
than a label, read from a ConfigMap rendered by `cluster-config-maps`.

## Test Locally

```bash
KUSTOMIZE_PLUGIN_HOME=$PWD/.tools/kustomize-plugin .tools/kustomize build \
  --enable-alpha-plugins --enable-helm --load-restrictor LoadRestrictionsNone \
  policies/stable/openshift-ai-models

make test
```
