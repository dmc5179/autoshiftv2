# open-webui

Deploys Open WebUI as the chat front end for the
Hermes Agent that the `hermes-agent` policy deploys. Users sign in to Open WebUI and talk to
Hermes, which is displayed as a single model named `hermes-agent`. Optionally, a second
connection offers a Models-as-a-Service model directly, next to Hermes. See
[Models-as-a-Service connection](#models-as-a-service-connection).

## Configuration

Enablement label `autoshift.io/open-webui`, plus `config.openWebui`. Every key is optional. The
policy also reads `config.hermesAgent` to find Hermes, and fails without it.

```yaml
config:
  openWebui:
    namespace: 'open-webui'
    auth: 'openshift'
    allowedGroups:
      - 'maas-users'
    adminEmail: 'alice@cluster.local'
    maas:
      model: 'granite-4-tiny-gpu'
```

| Field | Default | Notes |
|-------|---------|-------|
| `namespace` | `open-webui` | |
| `image` | the verified pin | v0.12.5, pinned by digest. Verify a new release under the `restricted-v2` SCC before changing it |
| `storageSize` | `10Gi` | Users, chats, uploads, the vector store and the seeded models |
| `storageClass` | cluster default | Set only to override the default StorageClass |
| `routeHost` | `<namespace>.<cluster ingress domain>` | Public hostname |
| `auth` | `local` | `local`: Open WebUI accounts. `openshift`: OpenShift credentials. See [Sign-in](#sign-in) |
| `allowedGroups` | `[maas-users]` | `openshift` only. OpenShift groups whose members can sign in |
| `proxyImage` | from ImageStream `openshift/oauth-proxy` | `openshift` only. Override for the proxy image |
| `adminEmail` | | Strongly recommended. See [Administrator](#administrator) |
| `adminSecretRef.name` / `.key` | `open-webui-admin` / `password` | `local` only. Secret holding the administrator password |
| `maas.model` | | Optional. A model name in `config.openshiftAiModels.models`, offered directly next to Hermes. See [Models-as-a-Service connection](#models-as-a-service-connection) |
| `maas.keyTtl` | `720h` | Lifetime of the MaaS key the pod mints, whole hours, at most `2160h` |
| `maas.renewBefore` | `168h` | How long before expiry the key is renewed. Must be shorter than `maas.keyTtl` |

## Sign-in

### `auth: openshift`

Users sign in with their OpenShift credentials, through the cluster's own oauth-proxy running as a
sidecar. Only members of `allowedGroups` get in. The default, `maas-users`, is the group that
`cluster-users.sh` adds users to. On a cluster without that group, set the list explicitly;
`system:authenticated` admits every user.

How it works:

- The proxy checks access with a SubjectAccessReview for `get` on the `open-webui-proxy` Service,
  made with the user's own token. A namespaced Role and RoleBinding grant that to
  `allowedGroups`, so the proxy's ServiceAccount needs no cluster-wide permissions and no
  `system:auth-delegator` binding.
- The proxy passes the user to Open WebUI in the `X-Forwarded-Email` and `X-Forwarded-User`
  headers. Open WebUI trusts them, so it listens on `127.0.0.1` only, reachable just from the
  proxy in the same pod. Its probes run inside the container for the same reason.
- An OpenShift user without an email address arrives as `<username>@cluster.local`. A user whose
  name is already an address keeps it.
- A new user starts with the `user` role, because `allowedGroups` already decided who gets in.
- The Route terminates TLS at the router and re-encrypts to the proxy, which serves a certificate
  from the service CA. A custom certificate on the default IngressController is picked up without
  a change here.
- Two proxy defaults are overridden: `--upstream-timeout` is 10 minutes instead of 30 seconds,
  because a Hermes agent turn can run tools for minutes, and `--pass-basic-auth` is off, because it
  would overwrite the `Authorization` header that Open WebUI's own API calls carry.

The proxy has no way to pass OpenShift groups or roles to Open WebUI, so an OpenShift group cannot
make someone an administrator. Further administrators are promoted in **Admin Panel > Users**.

Right after the OpenShift OAuth server rolls out, for example after any change to an identity
provider's Secret, sign-in can briefly fail at `/oauth/authorize` with `server_error` and
`resource name may not be empty`. That comes from the OAuth server, not from this policy, and
clears within a couple of minutes.

### `auth: local`

Open WebUI's own accounts, with sign-up and passwords.

## Administrator

Open WebUI makes the first account to sign up the administrator. `adminEmail` names that account
instead, and Open WebUI creates it at first start, only while no user exists, so the setting is
safe to leave in place.

**With `auth: openshift`**, set `adminEmail` to the proxy's address for an OpenShift user, which is
`<username>@cluster.local` for a user without an email address. That user signs in through
OpenShift as the administrator. No password Secret is involved: the account gets a random password
at creation, which nothing can use because sign-in always goes through the proxy.

**With `auth: local`**, the password comes from a Secret that an administrator creates in the
namespace, out of band:

```bash
oc create secret generic open-webui-admin -n open-webui --from-file=password=<file>
```

The pod does not start until that Secret exists, so the site is never reachable before its
administrator does. After the namespace is deleted, the policy re-creates the namespace and the pod
before anyone can re-create the Secret, so the pod waits in `CreateContainerConfigError` for a
moment and starts by itself once the Secret exists.

### Changing the administrator on an existing install

The administrator is stored in Open WebUI's database, so changing `adminEmail` later has no effect.
To move to `auth: openshift` with an existing local administrator, either change that account's
email in **Admin Panel > Users** to the proxy's address for the OpenShift user before switching, or
delete the namespace and let the policy start again with `adminEmail` set to that address. Deleting
the namespace deletes every user, chat and upload.

## Policies

| Policy | Mode | Does |
|--------|------|------|
| `policy-open-webui` | enforce | Namespace, the copied Hermes key, PVC, Deployment, Service and Route; with `auth: openshift`, also the proxy ServiceAccount and the sign-in Role and RoleBinding |
| `policy-open-webui-ready` | inform | The Deployment is Available, and with `auth: local` and `adminEmail` set, the administrator Secret exists |
| `policy-open-webui-maas-access` | inform | With `maas.model` set: the model's `accessGroups` let this namespace's ServiceAccounts mint a key, and its subscription exists |
| `policy-open-webui-maas-key` | inform | With `maas.model` set: the MaaS key exists, has not expired, and is not more than two hours overdue for renewal |

## How it connects to Hermes

In the cluster, at `http://hermes-agent.<hermes namespace>.svc.cluster.local:8642/v1`. Hermes has
no Route of its own.

The key it presents is Hermes' `API_SERVER_KEY`, copied on the managed cluster from the
`hermes-api-key` Secret into `open-webui-hermes`. The Hermes pod generates that Secret on first
start and never rotates it. That matters, because Open WebUI stores its connection settings in its
database on first start and ignores the environment afterward. A changed key would leave it using
the old one, which users see as an empty model list and `Model not found`.

## Settings applied for Hermes

| Setting | Why |
|---------|-----|
| Title, tag, follow-up, search-query and retrieval-query generation off | Open WebUI sends these to the chat model around every message. Against Hermes each one is a full agent turn of about 14,000 prompt tokens, and Hermes treats the prompt as a real request that it might act on and will remember |
| `ENABLE_OLLAMA_API=false` | There is no Ollama |
| `DEFAULT_MODELS=hermes-agent` | Preselects Hermes |
| `ENABLE_VERSION_UPDATE_CHECK=false` | No polling GitHub for new releases |
| `ENABLE_COMMUNITY_SHARING=false` | Removes the button that publishes a chat to openwebui.com |
| `BYPASS_MODEL_ACCESS_CONTROL=true` | Every user who can sign in sees every model. Open WebUI otherwise shows a connection's models to administrators only, until an administrator grants access model by model, so a new user would see an empty model list. Who can sign in is already decided by `allowedGroups` or by the administrator |

Most Open WebUI settings take effect on first start only. After that, change them in the Admin
Panel.

The per-user `X-Hermes-Session-Key` header is not configured. Hermes uses it only for its optional
Honcho memory provider, and the header value needs a template placeholder that policy templating
would consume. Add it in **Admin Panel > Settings > Connections** if Honcho is enabled.

## Models-as-a-Service connection

With `maas.model` set, Open WebUI gets a second OpenAI connection, to the Models-as-a-Service
gateway, and users can choose that model next to `hermes-agent`. It answers directly, without
Hermes' tools, memory or 14,000-token system prompt.

**Quota: every user shares one key, so every user shares one tokenRateLimit.** The pod mints a
single MaaS key with its ServiceAccount, and Models-as-a-Service counts tokens per key owner and
subscription. One heavy user can therefore exhaust the model's limit for all Open WebUI users.
Usage in MaaS is attributed to the ServiceAccount, not to the person; Open WebUI's own chat history
is the only per-user record. Hermes has its own key and owner, so it is not affected.

The model's `accessGroups` must include `system:serviceaccounts:<namespace>`, the group of the
pod's ServiceAccount (`open-webui-proxy` with `auth: openshift`, `open-webui` otherwise).
`policy-open-webui-maas-access` reports it.

How the key works, as for Hermes:

1. At start, a bootstrap in the Open WebUI container reuses the key stored in the
   `open-webui-maas-key` Secret, or mints and stores a new one. It passes both connections to Open
   WebUI in `OPENAI_API_BASE_URLS` and `OPENAI_API_KEYS`, Hermes first.
2. It starts Open WebUI under `timeout`, set to stop it when the key enters its renewal window.
   The container exits with status 124, the kubelet restarts it in the same pod, and step 1 mints
   the replacement and revokes the key it replaced. With the defaults that is one restart about
   every 22 days, and Open WebUI is unavailable for the minute it takes to start.
3. If no key can be minted, Open WebUI starts anyway with the Hermes connection only, and retries
   an hour later. `policy-open-webui-maas-key` reports the missing key meanwhile.

### Settings come from the policy, not the Admin Panel

A renewed key must reach Open WebUI at every start, but Open WebUI normally reads connection
settings from the environment on first start only. With `maas.model` set, the policy therefore
sets `ENABLE_PERSISTENT_CONFIG=False`, and Open WebUI takes every setting from the environment at
every start. The cost: a setting changed in the Admin Panel lasts only until the pod next restarts,
which includes each key renewal. Users, chats, uploads and per-model settings are stored data, not
settings, and are kept.

It also sets `ENABLE_SIGNUP=False`. Open WebUI turns signup off in its database once the first
account exists, and that stored value no longer applies; left at its default, the signup form
would let anyone who reaches the UI register a password account under an address nobody has used
yet, and be that user when its owner signs in. Trusted-header sign-in does not consult the flag.

### Adding it to an existing install

Set `maas.model` and add the group to the model's `accessGroups`. The Deployment changes, so the
pod restarts once and mints its key. Settings an administrator changed in the Admin Panel revert
to the policy's values at that restart; to keep one, set it in this policy, if it is exposed, or
accept the default. Removing `maas.model` later restores database-held settings as they were
before.

## OpenShift specifics

The image is built to run as root. Under `restricted-v2` it runs as an arbitrary UID, which needs
two changes:

- `HOME` moves to `/tmp`, because the image sets `HOME=/root`, which is mode 700.
- About 265 MB of embedding and speech models ship under `/app/backend/data`, which the PVC mount
  hides. The `seed-models` initContainer copies them onto the PVC once. Without it, Open WebUI
  downloads them from HuggingFace on first start, or on a disconnected cluster starts with document
  upload and retrieval broken.

The Route timeout is 10 minutes, because a Hermes agent turn can run tools for minutes and the
router default is 30 seconds.

## Data safety

`pruneObjectBehavior: None`. Turning the label off deletes nothing. Users, chats and uploads stay
on the PVC until the namespace is deleted by hand.
