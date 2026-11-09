# open-webui

Deploys Open WebUI as the chat front end for the
Hermes Agent that the `hermes-agent` policy deploys. Users sign in to Open WebUI and talk to
Hermes, which is displayed as a single model named `hermes-agent`.

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
