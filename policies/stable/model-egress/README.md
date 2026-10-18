# model-egress

Default-deny **outbound** network policy for the namespaces that run models and
agents, with an FQDN allowlist, a cluster-wide floor, and audit logging of what
gets blocked.

Everything else in the RHOAI stack controls **ingress** — who may call a model
(`MaaSAuthPolicy`), and how fast (`MaaSSubscription`, Kuadrant rate limits). This
is the other direction: what the model itself may reach.

Off by default. It is the policy here most capable of taking a working cluster
down.

## Why a CIDR is not enough

The motivating case: a model needs to reach a CDN whose range is `104.16.0.0/12`.
A `NetworkPolicy` `ipBlock` for that range permits every tenant of that CDN —
including one an attacker rented this morning. `NetworkPolicy` cannot express a
hostname; `EgressFirewall` can. That is why both are here and neither replaces the
other.

They also cover different traffic. `EgressFirewall` governs only packets leaving
the cluster, so lateral pod-to-pod movement still needs `NetworkPolicy`.

## Configuration

```yaml
config:
  modelEgress:
    baseline:
      enabled: true
      priority: 50
      subjectLabels:
        autoshift.io/ai-workload: 'true'
    zones:
      - namespace: 'llm'
        podSelector: {}
        aclLogging:
          deny: 'alert'
        allow:                      # NetworkPolicy egress rules, verbatim
          - to:
              - namespaceSelector:
                  matchLabels:
                    kubernetes.io/metadata.name: models-as-a-service
            ports:
              - protocol: TCP
                port: 8000
        egressFirewall:             # EgressFirewall rules, verbatim, in order
          - type: Allow
            to:
              dnsName: cdn.example.com
            ports:
              - protocol: TCP
                port: 443
```

Enable with `autoshift.io/model-egress: 'true'`.

## Four layers

| Policy | Mode | Does |
|--------|------|------|
| `policy-model-egress-baseline` | enforce | `AdminNetworkPolicy`: deny cloud metadata, allow cluster DNS, for every namespace labelled `autoshift.io/ai-workload` |
| `policy-model-egress-netpol` | enforce | Per zone: default-deny egress + an allowlist |
| `policy-model-egress-firewall` | enforce | Per zone: `EgressFirewall` with FQDN rules and a terminal deny |
| `policy-model-egress-audit` | enforce | Per zone: OVN ACL logging annotation and the workload label |
| `policy-model-egress-ready` | inform | OVN actually programmed the rules |

The **baseline** is the highest-value rule for the least risk. A model that can
reach `169.254.169.254` can read the node's instance credentials, which on AWS is
a direct path from prompt injection to the cloud account.

## Things that will catch you

**A terminal deny is mandatory, and the policy adds it.** With no `EgressFirewall`
present the default is Allow, and rules are evaluated in order — so an allowlist
with no trailing `Deny 0.0.0.0/0` permits everything while looking restrictive.
Do not add one in config; it is appended.

**DNS is always allowed and is not configurable.** A default-deny egress policy
without it gives a model that times out on every name lookup, and whoever debugs
that will be looking at the model, not at a network policy.

**Do not fence the MaaS namespaces.** `models-as-a-service` and
`redhat-ai-gateway-infra` run maas-api, Limitador and Authorino, all of which make
outbound calls. Breaking them surfaces as a 403 or 504 at the gateway.

**One `EgressFirewall` per namespace, named `default`.** The CRD pins
`metadata.name` to `^default$`, and each rule's `to` has `maxProperties: 1` — one
of `cidrSelector`, `dnsName` or `nodeSelector`, never two.

**DNS name resolution is TTL-polled**, with a 30-minute floor. A fast-rotating CDN
can produce both stale allows and spurious denies.

## What this does not close

**DNS exfiltration.** Allowing port 5353 to `openshift-dns` still lets data encoded
in subdomain labels reach CoreDNS, which forwards it upstream. The `EgressFirewall`
deny does not help, because that resolution leaves via the node rather than the
pod. Closing it needs CoreDNS forward-policy work, which is out of scope here.

**OCI modelcar pulls are unaffected**, which is intended — the kubelet pulls them on
the node network, outside pod egress policy. A model using an `s3://` or `https://`
`uri:` instead goes through a storage initializer *inside* the pod and **will** be
blocked unless allowed.

**Content, as opposed to connections.** NeMo Guardrails filters the inference
request path; it cannot see an outbound call an agent process makes. It lowers the
chance something asks to call out. This policy is what stops the call.
