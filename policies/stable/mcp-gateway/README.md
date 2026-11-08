# mcp-gateway

Creates MCP gateway instances on Red Hat Connectivity Link 1.5, and optionally registers MCP
servers with them. The MCP catalog in Red Hat OpenShift AI 3.5 deploys MCP servers; this policy
gives agents one authenticated endpoint that federates their tools.

Enabled by the `autoshift.io/mcp-gateway` label. **What** it creates comes from
`config.mcpGateway` in the cluster's rendered-config, not from labels. An instance is a structured
record, and a label is a string.

The MCP Gateway is a Technology Preview feature.

## What it does not install

No Operator. Connectivity Link 1.5 deploys the MCP Gateway controller itself, with Authorino,
Limitador and DNS, through the `KuadrantControlPlane` named `default`. The
[connectivity-link](../connectivity-link/README.md) policy installs Connectivity Link; set its
channel to `stable-1.5`, because 1.4 has no MCP Gateway.

This policy reads `KuadrantControlPlane` in an inform policy and never creates, changes or deletes
it. Deleting it removes every Connectivity Link component.

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      connectivity-link: 'true'
      connectivity-link-channel: stable-1.5
      mcp-gateway: 'true'
      mcp-gateway-servers: 'true'   # optional: register config.mcpGateway.servers
```

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.
Turning a label off stops management and removes nothing.

## Configuration

```yaml
config:
  mcpGateway:
    instances:
      - name: 'mcp-gateway'
        namespace: 'mcp-system'
        gateway:
          name: 'mcp-gateway'
          namespace: 'openshift-ingress'
          className: 'openshift-default'
          hostname: ''
          tlsSecretName: ''
          internalPort: 8080
        auth:
          type: 'kubernetes'
          audiences:
            - 'https://kubernetes.default.svc'
        logLevel: 'info'
        extraRouteNamespaces: []
    servers:
      - name: 'openshift-mcp'
        namespace: 'mcp-servers'
        instance: 'mcp-gateway'
        service: 'openshift-mcp'
        port: 8080
        path: '/mcp'
        prefix: 'ocp_'
        category:
          - 'platform'
        hint: 'Read-only OpenShift cluster tools'
        credentialSecret:
          name: 'openshift-mcp-credential'
          key: 'token'
```

Every value in the sample is an example.

| Field | Default | Notes |
|-------|---------|-------|
| `instances` | | Required, at least one |
| `instances[].name` | | Required. The `MCPGatewayExtension` name |
| `instances[].namespace` | | Required. Created by the policy. The broker runs here. One instance per namespace |
| `instances[].gateway.name` | `name` | |
| `instances[].gateway.namespace` | `openshift-ingress` | |
| `instances[].gateway.className` | `openshift-default` | |
| `instances[].gateway.hostname` | `<name>.<ingress domain>` | The public endpoint. The domain is read on the managed cluster |
| `instances[].gateway.tlsSecretName` | default IngressController certificate | Must be in the Gateway namespace |
| `instances[].gateway.internalPort` | `8080` | The `*.mcp.local` listener that server routes attach to |
| `instances[].auth.type` | | Required: `none`, `kubernetes` or `jwt` |
| `instances[].auth.audiences` | `[https://kubernetes.default.svc]` | `kubernetes` only |
| `instances[].auth.issuerUrl` | | Required with `jwt`. Also advertised as the OAuth authorization server |
| `instances[].logLevel` | `info` | Broker log level |
| `instances[].extraRouteNamespaces` | | More namespaces allowed to attach server routes |
| `servers` | | Required when `mcp-gateway-servers` is on |
| `servers[].name` | | Required. The registration name |
| `servers[].namespace` | | Required. Where the MCP server runs. Not created |
| `servers[].instance` | first instance | |
| `servers[].service` | `name` | The MCP server's Service |
| `servers[].port` | | Required. The Service port |
| `servers[].path` | `/mcp` | |
| `servers[].prefix` | | Required. Prepended to every tool name. Immutable |
| `servers[].category` | `[uncategorised]` | Used by the gateway's tool discovery |
| `servers[].hint` | | Short description for tool discovery |
| `servers[].credentialSecret.name` / `.key` | / `token` | A Secret created out of band |

The policies fail, and name the missing field, when `instances` is empty, an instance has no
`name`, `namespace` or valid `auth.type`, a `jwt` instance has no `issuerUrl`, or a server lacks
`name`, `namespace`, `port` or `prefix` or names an undefined instance. A placed policy with
nothing to create would otherwise report Compliant.

## Policies

| Policy | Mode | Does |
|--------|------|------|
| `policy-mcp-gateway-prereqs` | inform | The MCP Gateway CRDs are established and `KuadrantControlPlane` is `Ready`. Waits for `policy-rhcl-ready` |
| `policy-mcp-gateway` | enforce | Per instance: the namespace, `Gateway`, `ReferenceGrant`, `MCPGatewayExtension` and `AuthPolicy`. Also the shared `openshift-default` GatewayClass |
| `policy-mcp-gateway-ready` | inform | The EnvoyFilter CRD exists, each `Gateway` is `Programmed`, each `MCPGatewayExtension` is `Ready`, each `AuthPolicy` is `Enforced` |
| `policy-mcp-gateway-servers` | enforce | Per server: an `HTTPRoute` and an `MCPServerRegistration`. Placed only with `mcp-gateway-servers` |
| `policy-mcp-gateway-servers-ready` | inform | Each `MCPServerRegistration` is `Ready`, and each credential Secret exists with its label |

The prerequisite gate matters because a `ConfigurationPolicy` naming a kind whose CRD does not
exist reports Compliant while doing nothing. On Connectivity Link 1.4 the chain stays Pending
instead.

## How an instance is wired

Each instance gets its own `Gateway`, with two listeners:

- `mcp`, HTTPS on 443, is the public endpoint. The MCP Gateway controller creates the HTTPRoute
  for `/mcp` on it, and the `AuthPolicy` protects it.
- `mcp-internal`, HTTP, carries the `*.mcp.local` hostnames that server routes attach to. The broker
  reaches the servers through it, so `privateHost` points at it explicitly.

The internal listener accepts routes only from the instance namespace, the namespaces of the
configured servers, and `extraRouteNamespaces`, never from all namespaces. It is served by the same
Gateway Service as the public listener, so a route attached from any namespace would be reachable
without passing the `AuthPolicy`.

## Registering servers from the MCP catalog

The MCP Lifecycle Operator deploys a catalog server as an `MCPServer` with a Deployment and a
Service, and creates no route or registration. List the server under `config.mcpGateway.servers`
with its Service name and port; this policy adds an `HTTPRoute` with the hostname
`<namespace>-<name>.mcp.local` and an `MCPServerRegistration`.

To register servers by hand instead, leave `mcp-gateway-servers` off and add the namespace to
`extraRouteNamespaces`, so the route can attach.

A credential Secret is created out of band, never from values, and needs the label
`mcp.kuadrant.io/secret=true`. The broker uses it for tool discovery and never sends it with a
client's tool call.

## Authentication

`auth.type` has no default, so an unauthenticated tool endpoint is a decision someone wrote down.

- `kubernetes` validates OpenShift user tokens and ServiceAccount tokens through a TokenReview.
- `jwt` validates tokens from an OpenID Connect issuer, such as Red Hat build of Keycloak, and sets
  `oauthProtectedResource` so MCP clients discover the issuer.
- `none` creates no `AuthPolicy`.

The `AuthPolicy` excludes `/.well-known/oauth-protected-resource`, which clients read before they
have a token. The `AuthPolicy` uses `mustonlyhave`: under `musthave`, a changed `auth.type` would
leave the old method beside the new one, and a request passes when any method succeeds.

## Disconnected clusters

No images are named here. The MCP Gateway controller and broker images are related images of the
Connectivity Link 1.5 bundle, so mirroring the `rhcl-operator` package on channel `stable-1.5`
carries them.

## Verifying

```bash
oc get kuadrantcontrolplane default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
oc get mcpgatewayextensions.mcp.kuadrant.io -A
oc get mcpserverregistrations.mcp.kuadrant.io -A
oc get gateways.gateway.networking.k8s.io -n openshift-ingress
oc get authpolicies.kuadrant.io -n openshift-ingress
```
