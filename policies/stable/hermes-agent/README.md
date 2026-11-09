# hermes-agent

Deploys the Hermes Agent harness from Nous Research, which does its
thinking with a model served through Red Hat OpenShift AI Models-as-a-Service (MaaS). Hermes
exposes an OpenAI-compatible API in the cluster, which the `open-webui` policy connects to.

Hermes is an agent rather than a chat endpoint. It keeps memory, learns reusable skills and runs
tools, and it stores all of that on a persistent volume.

## Configuration

Enablement label `autoshift.io/hermes-agent`, plus `config.hermesAgent`:

```yaml
config:
  hermesAgent:
    model: 'granite-4-tiny-gpu'      # required: a model name in config.openshiftAiModels.models
    namespace: 'hermes'
    keyTtl: '720h'
    renewBefore: '168h'
    storageSize: '10Gi'
    storageClass: 'gp3-csi'
```

| Field | Default | Notes |
|-------|---------|-------|
| `model` | | Required. The name of a model in `config.openshiftAiModels.models`, not a request model id |
| `namespace` | `hermes` | Must match the ServiceAccount group in that model's `accessGroups` |
| `image` | the verified pin | Hermes image, pinned by digest |
| `keyTtl` | `720h` | Lifetime of the MaaS key the pod mints, at most `2160h`. See [Key renewal](#key-renewal) |
| `renewBefore` | `168h` | How long before expiry the key is renewed. Must be shorter than `keyTtl` |
| `storageSize` | `10Gi` | Memory, skills and conversation history |
| `storageClass` | cluster default | Set only to override the default StorageClass |
| `contextLength` | read from the gateway | Set only when Hermes cannot read the model's context window |

The rest is derived, so it cannot disagree with `openshift-ai-models`:

| Hermes needs | Derived from |
|--------------|--------------|
| Request model id | `publishers/<openshiftAiModels.namespace>/models/<model>`. The bare name returns 404 |
| Subscription to mint against | `<model>-default`, which `openshift-ai-models` creates |
| Gateway URL | The HTTPS listener hostname of `openshiftAiModels.gateway`, on the managed cluster |
| Gateway CA | `openshift-config-managed/default-ingress-cert`, copied on the managed cluster |

## Requirements

- `openshift-ai-models` serving the chosen model. `policy-hermes-agent` depends on
  `policy-openshift-ai-models-ready`.
- That model's `accessGroups` must include `system:serviceaccounts:<namespace>`, or a broader
  group such as `system:serviceaccounts` or `system:authenticated`. The default
  `system:authenticated` qualifies; a narrowed list must name the Hermes group explicitly.
- Hermes sends about 14,000 prompt tokens on every turn, because tool definitions, skills and
  memory travel with each request. Size the model's `tokenRateLimit` and context window for that.

## Policies

| Policy | Mode | Does |
|--------|------|------|
| `policy-hermes-agent` | enforce | Namespace, ServiceAccount, the `hermes-api-key` Role, PVC, gateway CA, bootstrap script, Deployment and Service |
| `policy-hermes-agent-access` | inform | The model grants the ServiceAccounts in this namespace, and its subscription exists |
| `policy-hermes-agent-ready` | inform | The Deployment is Available and its `hermes-api-key` Secret exists |
| `policy-hermes-agent-key` | inform | The MaaS key has not expired, and its renewal is not more than two hours overdue. Evaluated hourly rather than on change, because a key ages without any event |

## Credentials

None come from git or from this policy. RHACM policy templates have no random-number function,
so the pod handles both credentials itself at startup, in a bootstrap script that then starts
Hermes:

- **MaaS key.** Minted with the pod's own ServiceAccount token, so no person's credential is
  involved, and kept with its expiry in the `hermes-maas-key` Secret. The token is the
  automatically mounted one: a token requested with an explicit audience is rejected with a 401.
- **Hermes API key** (`API_SERVER_KEY`), which Open WebUI presents to Hermes. On first start the
  pod creates the `hermes-api-key` Secret with a random value, then reads it on every start. The
  Role grants `get` on both Secrets, `patch` on `hermes-maas-key`, and `create` on Secrets in
  this namespace.

Both keys exist only in the process environment and in those two Secrets.

## Key renewal

The key renews itself, with no CronJob and no person involved. Hermes reads the key from its
process environment, and a running process cannot take a new one, so renewal is a container
restart:

1. At start, the bootstrap reuses the stored key if it is outside its renewal window and was
   minted for the current gateway, subscription and `keyTtl`. Otherwise it mints a new key and
   stores it.
2. It starts Hermes under `timeout`, set to stop it when the key enters its renewal window,
   `renewBefore` ahead of expiry.
3. The container exits with status 124, the kubelet restarts it in the same pod, and step 1 mints
   the replacement.

With the defaults that is one restart about every 22 days (`720h` minus `168h`), taking well
under a minute. A restart count that climbs by one at that interval, with exit code 124, is
renewal working.

If maas-api refuses or cannot be reached when renewal is due, Hermes keeps running on the old key
while it is valid and retries in an hour, rather than going down early.
`policy-hermes-agent-key` reports a key that has expired, or whose renewal is more than two hours
overdue. Replaced keys are not revoked; each expires at the end of its own TTL.

`keyTtl` is capped at `2160h` because Models-as-a-Service in Red Hat OpenShift AI 3.5 rejects keys
longer than 90 days. The same keys and limits are used by the `openshell` policy.

## Updating

The Deployment is `mustonlyhave`: with `musthave`, an image or environment change merges into
`containers[]` and is silently never applied. Model settings live in the pod template, so changing
`model` rolls the pod. A ConfigMap change does not roll a pod, because RHACM templates have no hash
function. After changing the bootstrap script in `manifests/hermes-agent.yaml`, increment the
`autoshift.io/hermes-bootstrap-revision` annotation on the pod template in the same file.

## Data safety

`pruneObjectBehavior: None`. Turning the label off stops reconciliation and deletes nothing,
because the PVC holds everything Hermes has learned. Deleting Hermes is a deliberate manual step:
delete the namespace.

All users of a connected Open WebUI share one Hermes: its skills, its built-in memory and its
history. Deploy one Hermes per team where that matters.
