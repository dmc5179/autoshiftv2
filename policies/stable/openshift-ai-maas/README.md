# openshift-ai-maas AutoShift Policy

## Overview

Enables Models-as-a-Service on a cluster that already has Red Hat OpenShift AI, using AutoShift's
ACM **PolicyGenerator** pattern. MaaS puts an authenticating, rate-limiting gateway in front of
served models, so consumers reach them with an API key over the OpenAI API rather than talking to
an inference service directly.

This policy covers the platform. Deploying an actual model is
[openshift-ai-models](../openshift-ai-models/README.md).

## What it configures

- `DSCInitialization` and `DataScienceCluster` with the `aigateway` component and
  `modelsAsAService` managed
- The `maas-default-gateway` Gateway and its `GatewayClass`
- The PostgreSQL instance MaaS stores subscription and key state in
- The default `AITenant`

## Dependencies

Ordered by `policy-generator-config.yaml`, and all of them have to be in place first:

| Needs | Provided by |
|---|---|
| Red Hat OpenShift AI | [openshift-ai](../openshift-ai/README.md) |
| Red Hat Connectivity Link (Kuadrant, Authorino, Limitador) | [connectivity-link](../connectivity-link/README.md) |
| cert-manager | [cert-manager](../cert-manager/README.md) |
| Leader Worker Set | [leader-worker-set](../leader-worker-set/README.md) |
| User Workload Monitoring | [user-workload-monitoring](../user-workload-monitoring/README.md) |
| A `LoadBalancer` the gateway can claim | the cloud provider, or [metallb](../metallb/README.md) off-cloud |

On a non-cloud cluster the gateway cannot reach `Programmed=True` without MetalLB, and external
traffic additionally needs a passthrough Route.

## Labels

| Label | Meaning |
|---|---|
| `openshift-ai-maas` | enable on this cluster |

Declared in `autoshift/values/clustersets/_example.yaml`. Labels are set in values files only;
never on a `ManagedCluster` directly.

## Test Locally

```bash
KUSTOMIZE_PLUGIN_HOME=$PWD/.tools/kustomize-plugin .tools/kustomize build \
  --enable-alpha-plugins --enable-helm --load-restrictor LoadRestrictionsNone \
  policies/stable/openshift-ai-maas

make test
```
