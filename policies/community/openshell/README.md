# openshell

Deploys the OpenShell gateway, the control plane for running AI agents in isolated sandboxes, from
NVIDIA's upstream Helm chart on the Red Hat product-built images
(`quay.io/opendatahub/odh-openshell-*`).

> [!WARNING]
> OpenShell is a Developer Preview in Red Hat OpenShift AI 3.5. The release notes describe it as an
> experimental preview that "uses upstream artifacts and is not supported for production
> environments". This policy is in the community tier for that reason: there is no OperatorHub entry
> and no Red Hat support for the gateway. The operators it depends on are supported at their own
> levels: the Red Hat build of Agent Sandbox is a Technology Preview, and cert-manager Operator for
> Red Hat OpenShift is generally available.

## Policies

| Policy | Mode | What it does |
|---|---|---|
| `policy-openshell-prereqs` | inform | Barrier. The Sandbox API `agents.x-k8s.io/v1beta1` is served, the cert-manager CRDs exist, and a default StorageClass exists. Fails with a message naming what is missing |
| `policy-openshell-namespace` | enforce | Namespaces `openshell` (gateway and sandboxes) and `openshell-credentials` (provider credentials), and a copy of the cluster ingress signer for sandboxes to trust |
| `policy-openshell-gateway` | enforce | The rendered chart: gateway StatefulSet, Services, passthrough Route, cert-manager Issuers and Certificates, the certgen Job, RBAC, NetworkPolicy |
| `policy-openshell-gateway-ready` | inform | The server Certificate is Ready, the certgen Job succeeded, and the gateway StatefulSet has a ready replica |
| `policy-openshell-maas-provider` | enforce | Opt-in. The `rhoai-maas` provider profile, and a CronJob that creates the `rhoai-maas` provider and sandbox template and keeps the Models-as-a-Service key renewed |
| `policy-openshell-maas-provider-ready` | inform | Opt-in. The CronJob has completed at least one reconcile |

Each policy waits for the one before it. The barrier also depends on
`policy-agent-sandbox-operator-install` and `policy-cert-manager-operator-install`, and the provider
policy on `policy-openshift-ai-models-ready`.

## Enabling

```yaml
hubClusterSets:
  hub:
    labels:
      openshell: 'true'
      openshell-version: 'v0.1.6-rhaiv.4'
      openshell-maas: 'true'
      # Required on the same cluster. The autoshift chart fails the render without them.
      agent-sandbox: 'true'
      cert-manager: 'true'
      openshift-ai-maas: 'true'     # for openshell-maas
      openshift-ai-models: 'true'   # for openshell-maas
    config:
      openshell:
        maas:
          model: 'granite-4-tiny-gpu'   # a name in config.openshiftAiModels.models
```

| Label | Default | Meaning |
|---|---|---|
| `openshell` | `'false'` | Places these policies |
| `openshell-version` | `v0.1.6-rhaiv.4` | Image tag for the gateway, supervisor, sandbox runtime and command line interface |
| `openshell-maas` | `'false'` | Places the Models-as-a-Service provider policies |

| `config.openshell.maas` field | Default | Meaning |
|---|---|---|
| `model` | | Required with `openshell-maas`. A model name in `config.openshiftAiModels.models` |
| `keyTtl` | `720h` | Lifetime of each minted key, in whole hours. At most `2160h`: Models-as-a-Service in Red Hat OpenShift AI 3.5 rejects keys longer than 90 days |
| `renewBefore` | `168h` | Renew a key this long before it expires. Must be shorter than `keyTtl` |
| `schedule` | `*/15 * * * *` | How often the CronJob reconciles. A run with nothing to do mints nothing |
| `binaries` | curl, Python and Node at the usual paths | Executables in a sandbox allowed to use the key |

Set labels in values files only. The `cluster-labels` policy stamps them onto each cluster.

## Requirements

- OpenShift Container Platform 4.19.35, 4.20.26, 4.21.21, 4.22.2 or later in the same minor version.
  These are the Red Hat build of Agent Sandbox minimums. OpenShell itself needs 4.19 or later,
  because the Red Hat Enterprise Linux CoreOS kernels in 4.16 to 4.18 lack Landlock.
- Red Hat Enterprise Linux CoreOS worker nodes.
- A CNI that enforces ingress and egress NetworkPolicy, such as OVN-Kubernetes. OpenShell creates the
  policies but cannot verify that they are enforced.
- The hub's Red Hat OpenShift GitOps repository server must reach `ghcr.io` to pull the chart, and the
  managed cluster must reach `quay.io` and `registry.access.redhat.com` for images. For a
  disconnected cluster, mirror both and point `repo:` and the image registry at the mirror.

## Versions

The chart version is pinned in `manifests/chart/kustomization.yaml` and applies to every cluster,
because the hub renders the chart once. The image tag is per cluster. Each Red Hat build is made from
one upstream release, so move the two together: `v0.1.6-rhaiv.N` belongs with chart `0.1.6`.

## How the chart is rendered, and what that changes

The hub renders the chart offline with kustomize and PolicyGenerator, the same way the vault policy
renders its chart. Four chart behaviors depend on a live `helm install`, and the policy handles each:

| Chart behavior | Problem when rendered offline | What the policy does |
|---|---|---|
| Agent Sandbox preflight | Needs live API discovery | Turned off. `policy-openshell-prereqs` replaces it |
| Credential key-encryption key generated with `randBytes`, kept stable through a Helm `lookup` | A new key on every render. The policy would overwrite it, and every stored provider credential would become undecryptable | Uses the Kubernetes Secrets credential driver, which stores provider credentials as Secrets in `openshell-credentials` and needs no key |
| The certgen Job is a hook with a 300-second TTL that deletes itself | The policy would re-create it every few minutes | The TTL is removed |
| The certgen Job pod template is immutable | An image upgrade would leave the policy NonCompliant | The image tag is part of the Job name, so an upgrade creates a new Job. The key generation is idempotent |

The chart also leaves five objects without `metadata.namespace`, which a patch sets, and it fixes
the gateway's user and group ID at 1000, which `restricted-v2` rejects. The chart's documented
override sets them to `null`, but kustomize drops `null` values before Helm sees them, so a patch
removes both fields from the rendered StatefulSet instead.

### Two compliance types in one policy

`policy-openshell-gateway` renders the chart once in `manifests/chart/` and splits the output in two:

| Part | Compliance type | Why |
|---|---|---|
| `manifests/statefulset/`: the gateway StatefulSet | `mustonlyhave` | `musthave` merges into lists and never replaces an entry, so a new image tag or env value would not reach the gateway container. With `mustonlyhave`, changing `openshell-version` rolls the gateway |
| `manifests/gateway/`: everything else | `musthave` | Controllers add to some of these objects after creation. The certgen Job, for example, gets controller labels and has an immutable pod template, so `mustonlyhave` would leave it NonCompliant |

A StatefulSet's `volumeClaimTemplates` cannot be changed after creation, so the StatefulSet part
writes every field the API server fills in there, and the defaulted update strategy and retention
policy, with the values the server stores. The template then matches the live object, and
`mustonlyhave` never asks for a change the API server would reject. A marker annotation,
`autoshift-openshell/manifest: statefulset`, separates the two parts, so an object kind added by a
future chart goes to the `musthave` part rather than to both.

## Security choices

- `server.auth.allowUnauthenticatedUsers` is always `false`. Until OpenID Connect is configured, the
  command line interface signs in with the mutual TLS client bundle in the `openshell-client-tls`
  Secret.
- Provider credentials live in their own namespace, `openshell-credentials`, because the credential
  driver's Role can read and write every Secret in its namespace.
- The default sandbox image is `registry.access.redhat.com/ubi9/ubi-minimal`, not the chart's
  `nvcr.io/nvidia/base/ubuntu`, which `global.image.registry` does not redirect. Agents pass their own
  image with `openshell sandbox create --from`.
- No security context constraint grant. Since OpenShell 0.1.0 every pod runs under `restricted-v2`.

## Models-as-a-Service

OpenShell 0.1.6 has no inference router. Sandboxes call a model provider's own endpoint, and the
sandbox proxy substitutes the real credential only on requests that a provider profile allows. With
`openshell-maas` on, this policy supplies:

- **The `rhoai-maas` provider profile.** It binds an `OPENAI_API_KEY` bearer credential to the
  Models-as-a-Service gateway host, port 443, under `/v1`, and lists the executables allowed to use
  it. A request anywhere else that carries the placeholder gets HTTP 403
  `credential_endpoint_mismatch`.
- **The `rhoai-maas` provider**, holding a Models-as-a-Service key. The
  CronJob mints the key with its ServiceAccount token against the `<model>-default` subscription, the
  same way the hermes-agent policy mints its key. It mints a new key when the provider is missing,
  when the key is inside its renewal window, or when the profile, gateway URL, subscription or
  lifetime changed. Running sandboxes pick up a renewed key.

  Once the new key is stored in the provider and recorded, the CronJob revokes the key it replaced,
  so at most one key is valid at a time. A key belongs to the ServiceAccount that minted it, so no
  extra permission is needed. A failed revocation is a warning, not a failure, and that key lapses at
  the end of its own lifetime.

  ConfigMap `openshell/openshell-maas-provider-state` records `expiresAt` and `mintedAt` (epoch
  seconds), `configHash`, and `keyId`, the id of the current key. State written before `keyId` was
  recorded has none, so the first renewal after an upgrade cannot revoke the key it replaces; every
  renewal after that does.
- **The `rhoai-maas` sandbox template**, which sets `OPENAI_BASE_URL` to the gateway's `/v1` URL. A
  provider's configuration values do not reach the sandbox environment in OpenShell 0.1.6: only
  credentials do, and only the built-in Google profiles project configuration. A template can carry
  a non-secret environment variable, so the URL travels there and the key stays with the provider.

Requirements:

- The model's `accessGroups` in `config.openshiftAiModels` must include
  `system:serviceaccounts:openshell`. Sandbox workloads get no ServiceAccount token, so this does not
  let a sandbox mint keys.
- Sandboxes draw on the model's subscription quota, which every consumer of that model shares. On a
  model with a 50,000 token per minute limit, one agent turn of about 14,000 prompt tokens uses over a
  quarter of it, so size `tokenRateLimit` for every consumer, not for OpenShell alone.
- The gateway must not have OpenID Connect enabled. The CronJob signs in with the mutual TLS client
  bundle, which makes it a platform administrator only while OpenID Connect is off.

A sandbox uses the model when it is created from the template with the provider attached. Inside
it, `OPENAI_BASE_URL` points at the gateway and `OPENAI_API_KEY` holds the placeholder, so the
OpenAI SDK works unchanged. Attaching the provider alone gives the key but not the URL. The request
model ID is `publishers/<openshiftAiModels.namespace>/models/<model>`. Single quotes keep the
variables from expanding on your own machine:

```shell
openshell sandbox create --name agent --template rhoai-maas --provider rhoai-maas -- sleep 600
openshell sandbox exec --name agent -- \
  sh -c 'curl -sS "$OPENAI_BASE_URL/models" -H "Authorization: Bearer $OPENAI_API_KEY"'
```

### Testing a renewal

To see a renewal and its revocation without waiting weeks, move the recorded expiry into the
renewal window and run the CronJob once:

```shell
oc -n openshell patch configmap openshell-maas-provider-state --type merge \
  -p "{\"data\":{\"expiresAt\":\"$(( $(date +%s) + 3600 ))\"}}"
oc -n openshell create job openshell-maas-provider-renew-test --from=cronjob/openshell-maas-provider
oc -n openshell logs -f job/openshell-maas-provider-renew-test
oc -n openshell delete job openshell-maas-provider-renew-test
```

The log shows `minting a new key: key expires at ...`, then `provider rhoai-maas has a new key`,
then `revoked the replaced MaaS key <id>`. The run records the new expiry, so the next scheduled
run does nothing. Only the expiry is changed, and the real key is untouched until the run replaces
it. The first test after upgrading from a version that did not record `keyId` mints but cannot
revoke; run it twice to see the revocation.

### Trusting the cluster ingress certificate

The sandbox proxy verifies the destination certificate against its own truststore. On a cluster
that uses the operator-generated ingress certificate, that store does not contain the signer, so
calls to the Models-as-a-Service gateway would fail. The namespace policy copies
`openshift-config-managed/default-ingress-cert` into `openshell-additional-ca`, and the gateway hands
it to every sandbox through `[openshell.supervisor.network] additional_ca_bundle`. Chart 0.1.7 has a
value for this; chart 0.1.6 does not, but the `v0.1.6-rhaiv` builds already support it, so the
policy wires the configuration table, the mount and a ConfigMap rule on the sandbox Role by hand. A
changed signer reaches running sandboxes only after the gateway pod restarts and each sandbox is
stopped and started.

The bundle is additive: sandboxes keep trusting the public roots in the supervisor image. A cluster
whose ingress certificate is already publicly signed, for example by Let's Encrypt, needs none of
this, and keeps working with it, because the gateway accepts any bundle of PEM certificates. The
gateway refuses to start if the bundle holds anything else, such as comment lines or a private key;
`default-ingress-cert` holds only certificates.

## Verifying

`policy-openshell-gateway-ready` being Compliant means the gateway is serving. It does not prove that
sandboxes work. The supervisor and sandbox runtime images are pulled only when the first sandbox is
created, so a wrong tag or a missing mirror shows up there and nowhere else. Connect the command line
interface and create one sandbox:

```shell
ROUTE_HOST=$(oc -n openshell get route openshell -o jsonpath='{.spec.host}')
openshell gateway add "https://${ROUTE_HOST}" --local --name openshift
MTLS=~/.config/openshell/gateways/openshift/mtls
mkdir -p "${MTLS}"
oc -n openshell get secret openshell-client-tls -o jsonpath='{.data.ca\.crt}'  | base64 -d > "${MTLS}/ca.crt"
oc -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > "${MTLS}/tls.crt"
oc -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d > "${MTLS}/tls.key"
openshell status
openshell sandbox create --name hello -- echo "hello from a sandbox"
openshell sandbox delete hello
```

## Limitations

- OpenID Connect breaks the Models-as-a-Service CronJob. It signs in with the mutual TLS client
  bundle, which is a platform administrator only while OpenID Connect is off. With OpenID Connect on,
  that bundle no longer signs anyone in, and the CronJob needs an OpenID Connect client credential
  with the administrator role instead.
- Zero Trust Workload Identity Manager, which the agent identity flow needs, is not supported on
  clusters in FIPS mode (Red Hat Knowledgebase solution 7144070).

## Not yet covered

- OpenID Connect sign-in through the Red Hat build of Keycloak, and agent identity through
  Zero Trust Workload Identity Manager.
- An external PostgreSQL database for more than one gateway replica.
