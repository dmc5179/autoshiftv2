# mcp-gateway AutoShift Policy

## Overview

Installs the MCP Gateway Operator, which provides centralized routing and
access control for Model Context Protocol servers.

## Why this is its own policy

The MCP Gateway Operator is **not** part of Red Hat OpenShift AI and is not
installed by enabling the MCP Lifecycle Operator. The RHOAI 3.5 docs are
explicit that a cluster administrator installs and upgrades it
independently of the OpenShift AI operator lifecycle, so it gets its own
policy and its own label rather than riding along with `openshift-ai`.

It is a prerequisite for MCP server routing. The
[openshift-ai](../openshift-ai/README.md) `openshift-ai-mcp-catalog` label
enables the catalog and its lifecycle operator; without this gateway, MCP
servers deploy but are not routed through a gateway.

## Prerequisites

- OpenShift 4.19 to 4.22
- Red Hat OpenShift AI 3.5

Installing it pulls in its own required Red Hat Connectivity Link version as
a dependency. Worth knowing if
[connectivity-link](../connectivity-link/README.md) is also enabled, since
both then have an opinion about which RHCL is installed.

## Technology Preview

The operator ships on a `preview` channel and is Technology Preview — no
production SLA, and it may not be functionally complete.

## Verification

The policy asserts the two CRDs the docs name as the install check:

```
mcpgatewayextensions.mcp.kuadrant.io
mcpserverregistrations.mcp.kuadrant.io
```

## Labels

| Label | Meaning |
|---|---|
| `mcp-gateway` | enable on this cluster |

Plus the standard operator labels (`-subscription-name`, `-channel`,
`-source`, `-source-namespace`, `-version`), declared in
`autoshift/values/clustersets/_example.yaml`.

## Test Locally

```bash
KUSTOMIZE_PLUGIN_HOME=$PWD/.tools/kustomize-plugin .tools/kustomize build \
  --enable-alpha-plugins --enable-helm --load-restrictor LoadRestrictionsNone \
  policies/stable/mcp-gateway

make test
```
