# model-egress

Denies the cloud metadata endpoint to the namespaces that run models and agents.

Everything else in the RHOAI stack controls **ingress** — who may call a model
(`MaaSAuthPolicy`), and how fast (`MaaSSubscription`, Kuadrant rate limits). This
is the other direction: what the model itself may reach.

Off by default.

## Why this rule first

A model that can reach `169.254.169.254` can read the node's instance
credentials. On AWS that is a direct path from prompt injection to the cloud
account — the model is talked into fetching a URL, and the attacker has a
credential.

It is also the cheapest rule to turn on. No legitimate workload in a model
namespace has any reason to call the metadata service, so denying one link-local
address breaks nothing. That combination — high value, near-zero blast radius —
is why it ships alone rather than as part of a broader egress posture.

## Configuration

```yaml
config:
  modelEgress:
    baseline:
      enabled: true
      priority: 50
    namespaces:
      - 'llm'
```

Enable with `autoshift.io/model-egress: 'true'`.

Each listed namespace is labelled `autoshift.io/ai-workload`, which is what the
`AdminNetworkPolicy` selects on.

**Do not list `models-as-a-service` or `redhat-ai-gateway-infra`.** maas-api,
Limitador and Authorino all make outbound calls, and breaking them surfaces as a
403 or 504 at the gateway rather than as anything network-shaped.

## What it creates

| | |
|---|---|
| `policy-model-egress-baseline` | One cluster-scoped `AdminNetworkPolicy` denying `169.254.169.254/32` and `fd00:ec2::254/128`, plus an explicit cluster-DNS allow |

DNS is allowed even though an `AdminNetworkPolicy` with only a `Deny` rule leaves
other traffic to the cluster default. It is there so that adding a default-deny
layer later cannot silently break name resolution — a failure that presents as a
broken model, not as a network problem.

`v1alpha1` is the only version OpenShift 4.22 serves for this kind.

## Not covered yet

Deliberately out of scope here. Each is worthwhile, and each can take a working
cluster down if a rule is wrong, so they are tracked and staged separately rather
than bundled in:

- **Default-deny egress with an allowlist** (`NetworkPolicy`). The real lockdown,
  and the real risk.
- **FQDN allowlisting** (`EgressFirewall`). The reason a CIDR is not enough: an
  `ipBlock` for a CDN range permits every tenant of that CDN, including one an
  attacker rented this morning. Only `EgressFirewall` matches a hostname. Note it
  governs only traffic leaving the cluster, so it does not replace
  `NetworkPolicy` — they cover different halves.
- **ACL audit logging** (`k8s.ovn.org/acl-logging`), so a blocked attempt is a log
  line rather than a silence.
- **A readiness assertion** that OVN actually programmed the rules. An
  `EgressFirewall` object can exist unenforced, and the policy that created it
  still reports Compliant.

Two things that will matter when that work lands, learned while prototyping it:

- A terminal `Deny 0.0.0.0/0` is **mandatory**. With no `EgressFirewall` present
  the default is Allow and rules evaluate in order, so an allowlist without one
  permits everything while looking restrictive.
- One `EgressFirewall` per namespace, named `default` — the CRD pins
  `metadata.name` to `^default$`, and each rule's `to` has `maxProperties: 1`.

## What this cannot close

**DNS exfiltration.** Data encoded in subdomain labels still reaches CoreDNS,
which forwards it upstream. That resolution leaves via the node, so no pod-level
egress rule sees it. Closing it needs CoreDNS forward-policy work.

**Content, as opposed to connections.** NeMo Guardrails filters the inference
request path; it cannot see an outbound call an agent process makes. It lowers
the chance something asks to call out. Network policy is what stops the call.
