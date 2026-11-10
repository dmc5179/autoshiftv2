# rhokp-mcp

Deploys a dedicated Red Hat Offline Knowledge Portal (RHOKP) and the RHEL Knowledge Bridge MCP
server in front of it, so that an MCP client can search Red Hat documentation, solutions,
articles, CVEs and errata offline. Register the server with the
[mcp-gateway](../../stable/mcp-gateway/README.md) policy and point clients at the gateway, for
example OpenShift Lightspeed through
[openshift-lightspeed](../../stable/openshift-lightspeed/README.md).

Enabled by the `autoshift.io/rhokp-mcp` label. What it deploys comes from `config.rhokpMcp`, and
every key has a default.

## Support status

This is a community policy:

- The RHEL Knowledge Bridge image is documented only as part of the command-line assistant for
  disconnected environments in RHEL 10, which is a Developer Preview. No OpenShift deployment of it
  is documented.
- RHOKP is a supported product, but its access key requires a Satellite Infrastructure
  subscription (SKU MCT3718). Without a key, search does not work at all.
- RHOKP's content is for internal use only. Do not expose it, or the MCP server, outside the
  cluster.

Red Hat plans an MCP endpoint in RHOKP itself (UIECCP-1648, OLS-4714). When it ships, change the
MCP gateway's server entry to point at RHOKP and remove the knowledge bridge; clients that go
through the gateway do not change.

## Policies

| Policy | Mode | Depends on | Does |
|--------|------|------------|------|
| `policy-rhokp-mcp-prereqs` | inform | | The access key Secret exists, with a non-empty key. The message names the command to create it |
| `policy-rhokp-mcp-ns` | enforce | | The namespace, two ServiceAccounts without API tokens, and the NetworkPolicies |
| `policy-rhokp-server` | enforce | `-prereqs`, `-ns` | The RHOKP Deployment and Service (8080 HTML mirror, 8983 Solr) |
| `policy-rhokp-server-ready` | inform | `-server` | RHOKP is Available, meaning its search index has documents |
| `policy-rhokp-mcp` | enforce | `-server-ready` | The MCP server Deployment, Service (8000) and disruption budget |
| `policy-rhokp-mcp-ready` | inform | `-mcp` | Every MCP replica is Available |

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      rhokp-mcp: 'true'
    config:
      rhokpMcp:
        maxResponseChars: 12000
```

Then create the access key Secret, below. Turning the label off stops management and removes
nothing.

## Configuration

| Key | Default | Notes |
|---|---|---|
| `namespace` | `rhokp` | Created by the policy |
| `accessKeySecret` | `rhokp-access-key` | Secret in `namespace`, created out of band. The name Lightspeed's own RHOKP uses |
| `accessKeySecretKey` | `ACCESS_KEY` | The key in that Secret |
| `rhokpImage` | `registry.redhat.io/offline-knowledge-portal/rhokp-rhel9@sha256:1ac156d3…` | Tag 1.3.0-1793303796. Must be pinned by digest |
| `mcpImage` | `registry.redhat.io/rhel-cla/rhel-knowledge-bridge-rhel10@sha256:99fd47d0…` | Tag v1.0.2-1793868366. Must be pinned by digest |
| `rhokpCpuRequest` | `1` | |
| `rhokpMemoryRequest` / `rhokpMemoryLimit` | `2Gi` / `4Gi` | |
| `solrStorageRequest` / `solrStorageLimit` | `20Gi` / `75Gi` | Ephemeral storage request, and the index `emptyDir` size limit |
| `mcpReplicas` | `2` | 1 to 9 |
| `logLevel` | `INFO` | The MCP server's |
| `maxResponseChars` | the server's 30000 | Characters in one tool result |
| `excludeKbase` | `false` | Omit solutions and articles, for a content set without them |
| `clientNamespaces` | | More namespaces allowed to call the MCP server directly, besides the gateway's |

The policies fail, and name the key, when the namespace is not a valid name, an image is not
pinned by digest, a resource value is not a quantity, or `mcpReplicas`, `logLevel` or
`maxResponseChars` is out of range. They also fail when the cluster's rendered-config ConfigMap is
missing.

## The access key

The key is a licensed credential, so it never comes from Git or values. Create the Secret once
`policy-rhokp-mcp-ns` has created the namespace, from a file so the key does not appear in a
command line:

```bash
oc create secret generic rhokp-access-key -n rhokp --from-file=ACCESS_KEY=<file holding the key>
```

`policy-rhokp-mcp-prereqs` reports the Secret or the key missing, and nothing is deployed until it
exists. It never reads the value. To rotate the key, replace the Secret and restart RHOKP:
`oc rollout restart deployment/rhokp-server -n rhokp`. A restart rebuilds the index.

## Readiness that means search works

Each of these would otherwise report success while broken:

- **RHOKP without a valid key** starts, answers HTTP 200 and has an empty search index. Its
  readiness probe queries the `portal` core, the one the MCP server reads, and passes only when it
  holds documents. `policy-rhokp-server-ready` therefore means search returns results.
- **The MCP server with Solr unreachable** starts and answers every query with nothing. It is
  deployed only after `policy-rhokp-server-ready`.
- **An MCP pod that is Ready** has not necessarily listed tools for anyone. The MCP gateway's
  `MCPServerRegistration` Ready condition, in `policy-mcp-gateway-ready`, is the end-to-end check.

Both Deployments use `mustonlyhave`, because `musthave` merges into `containers[]` and would never
apply an image or setting change.

## Network

Neither workload has authentication, and the knowledge bridge has no TLS. No Route is created, and
NetworkPolicies admit:

| To | From |
|---|---|
| RHOKP 8080 and 8983 | the MCP server pods |
| MCP server 8000 | `openshift-ingress` (the gateway's Envoy pods, which route tool calls), the MCP gateway namespace from `config.mcpGateway.gateway.namespace` (the broker, which lists tools), and `clientNamespaces` |

RHOKP has no egress. The MCP server may reach only RHOKP and cluster DNS. To let Lightspeed call
the server directly rather than through the gateway, add `openshift-lightspeed` to
`clientNamespaces`.

## Capacity and updates

RHOKP is a 7 to 10 GB image that indexes on every start, on an `emptyDir`. Expect about one CPU,
2 to 4 GiB of memory and tens of GiB of node ephemeral storage. Red Hat publishes new content
about weekly. Bump `rhokpImage` on a schedule you choose: every bump is a fresh pull and a
re-index, and a disconnected cluster must mirror the same digest first, or the only symptom is
`ImagePullBackOff`.

## Verifying

```bash
oc get deployments -n rhokp
# Solr has documents: the same check as the readiness probe
oc exec -n rhokp deploy/rhokp-server -- curl -s 'http://127.0.0.1:8983/solr/portal/select?q=*:*&rows=0&wt=json' \
  | jq .response.numFound
```

The MCP server is reachable only from the allowed namespaces, so test its tools through the MCP
gateway. See the mcp-gateway README.

## Not yet verified on a cluster

- `curl` and `grep` exist in the RHOKP 1.3 image (they do in the image Lightspeed ships). If not,
  the probe fails and RHOKP never becomes ready; it never falsely passes.
- How much ephemeral storage the indexed core takes, which `solrStorageRequest` should match.
- That the image indexes into `/var/solr/data`, as Lightspeed's RHOKP does.
- The knowledge bridge on a FIPS cluster.
