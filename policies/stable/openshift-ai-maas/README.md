# openshift-ai-maas

Turns on Models-as-a-Service (MaaS) in Red Hat OpenShift AI, creates the gateway it serves models
through, and reports whether the MaaS control plane behind it came up.

MaaS puts an authenticating, rate-limiting gateway in front of served models. Consumers reach a
model with an API key over the OpenAI API rather than calling an inference service directly.
OpenShift AI deploys the MaaS components itself once its `DataScienceCluster` enables
`aigateway.modelsAsAService`. This policy sets that field, and supplies what the product leaves to
the administrator: the `Gateway` those components attach to.

Deploying a model behind the gateway is [openshift-ai-models](../openshift-ai-models/README.md).

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-openshift-ai-maas` | enforce | The `openshift-default` GatewayClass, the `maas-gateway-options` ConfigMap and the `maas-default-gateway` Gateway in `openshift-ingress` |
| `policy-openshift-ai-maas-dsc` | enforce | `aigateway.modelsAsAService.managementState: Managed` in the `default-dsc` `DataScienceCluster`. Waits for `policy-openshift-ai-dsc` |
| `policy-openshift-ai-maas-ready` | inform | The Gateway reports `Programmed=True` |
| `policy-openshift-ai-maas-db` | inform | The maas-api database Secret exists, and the `maas-api` Deployment is `Available` |

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      openshift-ai: 'true'
      openshift-ai-maas: 'true'
      openshift-ai-maas-db-namespace: redhat-ai-gateway-infra   # optional
      openshift-ai-maas-db-secret: maas-db-config               # optional
```

| Label | Default | Meaning |
|---|---|---|
| `openshift-ai-maas` | | Enables these policies. Turning it off stops them managing anything and removes nothing |
| `openshift-ai-maas-db-namespace` | `redhat-ai-gateway-infra` | Namespace of `maas-api` and its database Secret. On Red Hat OpenShift AI 3.4 this was `redhat-ods-applications` |
| `openshift-ai-maas-db-secret` | `maas-db-config` | Name of the database Secret |

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

## Turning MaaS on, and off

The [openshift-ai](../openshift-ai/README.md) policy creates the `default-dsc`
`DataScienceCluster` with `aigateway` `Managed` and leaves `modelsAsAService` out.
`policy-openshift-ai-maas-dsc` patches that same object with only:

```yaml
spec:
  components:
    aigateway:
      modelsAsAService:
        managementState: Managed
```

Both policies use `musthave`, which merges only the fields each one lists, so each owns a different
field of one object and neither overwrites the other. The patch depends on `policy-openshift-ai-dsc`
being Compliant, because `musthave` creates a missing object: run first, it would create a
`default-dsc` holding nothing but this field.

With the label on, MaaS is `Managed`. With it off, these policies are no longer placed and stop
managing anything, and nothing is removed: MaaS keeps running, as with most AutoShift labels. To
remove MaaS, turn the label off and then set `modelsAsAService` to `Removed` in the
`DataScienceCluster` yourself.

## The gateway

The listener hostname is `maas.<ingress domain>`, discovered on the managed cluster, so the policy
needs no per-cluster DNS. The domain comes from the cluster `Ingress` configuration
(`ingresses.config.openshift.io/cluster`), which is always populated. The default
`IngressController` `spec.domain` is not: it is set only when someone configures it, and a template
reading it renders `maas.%!s(<nil>)`, which the API server rejects as a hostname.

The HTTPS listener serves the default `IngressController` certificate, falling back to
`router-certs-default` on a cluster still using the generated one.

Both listeners admit routes only from namespaces labeled
`maas.opendatahub.io/gateway-access: 'true'`. A model's `HTTPRoute` in an unlabeled namespace is
created without error, and the gateway answers 404. The `openshift-ai-models` policy labels its
namespace.

`maas-gateway-options` raises the gateway pod's `istio-proxy` resources. With the default request
the gateway runs out of memory under load, which presents as intermittent connection resets rather
than anything pointing at memory.

## The database Secret

maas-api stores API keys and subscription state in PostgreSQL. It reads the connection URL from a
Secret once, at startup, and exits when the Secret is missing:

```
error: failed to load database URL: failed to read secret
redhat-ai-gateway-infra/maas-db-config: secrets "maas-db-config" not found
```

The pod then restarts indefinitely, and authenticated requests to the gateway return
`no healthy upstream`. The Gateway is still `Programmed`, and every enforcing policy is still
Compliant. `policy-openshift-ai-maas-db` exists to report this at the layer that owns it.

No policy creates the Secret, because the URL carries a password. Create it out of band, with the
URL under the key `DB_CONNECTION_URL`, then restart maas-api:

```bash
oc create secret generic maas-db-config -n redhat-ai-gateway-infra \
  --from-literal=DB_CONNECTION_URL='postgresql://USER:PASSWORD@HOST:5432/DB'
oc rollout restart deployment/maas-api -n redhat-ai-gateway-infra
```

Any PostgreSQL that maas-api can reach works: a managed cloud database, or one in the cluster.

The `maas-api` check matters separately from the Gateway check. Serving and governance are separate
paths through the same gateway: with maas-api down, a model keeps answering requests made with an
existing key, while API key issuance, the model listing and subscription enforcement stop.

## Dependencies

`policy-openshift-ai-maas` depends on `policy-openshift-ai-operator-install`, and
`policy-openshift-ai-maas-dsc` on `policy-openshift-ai-dsc`, both from
[openshift-ai](../openshift-ai/README.md). The rest are runtime requirements that no `dependencies`
entry expresses:

| Needs | Provided by |
|---|---|
| Red Hat OpenShift AI and its `DataScienceCluster` | [openshift-ai](../openshift-ai/README.md) |
| Red Hat Connectivity Link: Kuadrant, Authorino and Limitador | [connectivity-link](../connectivity-link/README.md) |
| LeaderWorkerSet, for distributed inference | [leader-worker-set](../leader-worker-set/README.md) |
| cert-manager, which the OpenShift AI operator requires | [cert-manager](../cert-manager/README.md) |
| A `LoadBalancer` the gateway can claim | the cloud provider, or [metallb](../metallb/README.md) elsewhere |

Without a load balancer the Gateway never reaches `Programmed`, and `policy-openshift-ai-maas-ready`
stays NonCompliant. External traffic to a gateway outside a cloud additionally needs a passthrough
Route.

## Verifying

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.aigateway.modelsAsAService}{"\n"}'
oc get gateway maas-default-gateway -n openshift-ingress
oc get deployment maas-api -n redhat-ai-gateway-infra
oc get secret maas-db-config -n redhat-ai-gateway-infra
```
