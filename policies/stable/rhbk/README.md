# rhbk

Installs the Red Hat build of Keycloak Operator. A remote OpenShell gateway authenticates command
line users over OpenID Connect, not mutual TLS, so it needs an identity provider. Port-forwarded
access works without one, but only as an evaluation path.

This policy installs the Operator only. It creates no `Keycloak` instance, realm or client: those
are specific to the gateway that uses them. See [agent-sandbox](../agent-sandbox/README.md) for how
the OpenShell operator policies fit together.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-rhbk-operator-install` | enforce | The `rhbk-operator` namespace, an OwnNamespace OperatorGroup and the `rhbk-operator` subscription |

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      rhbk: 'true'
      rhbk-subscription-name: rhbk-operator
      rhbk-channel: stable-v26.6
      rhbk-source: redhat-operators
      rhbk-source-namespace: openshift-marketplace
      # rhbk-version: 'rhbk-operator.v26.6.7'   # optional CSV pin
```

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

OpenShell's demonstration material runs a plain `keycloak-rhel9` image. Its own validation guidance
says to use the Operator in production, which is what this policy installs.

## Install mode

Checked against the catalog on OpenShift 4.22, `rhbk-operator` v26.6.7:

```
OwnNamespace=True  SingleNamespace=True  MultiNamespace=False  AllNamespaces=False
```

AllNamespaces is not supported, so this policy sets `targetNamespaces: [rhbk-operator]`. Without it,
the shared operator-install chart's default produces a cluster-scoped OperatorGroup that OLM
refuses. The CSV then sits in `Failed` with `UnsupportedOperatorGroup` while the policy reports only
that the CSV was not found.

The Operator manages `Keycloak` resources in its own namespace, so create instances in
`rhbk-operator`.

## Verifying

```bash
oc get csv -n rhbk-operator
oc get crd keycloaks.k8s.keycloak.org
```
