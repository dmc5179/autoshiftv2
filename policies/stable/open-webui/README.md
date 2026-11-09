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
    adminEmail: 'admin@example.com'
    adminSecretRef:
      name: 'open-webui-admin'
      key: 'password'
```

| Field | Default | Notes |
|-------|---------|-------|
| `namespace` | `open-webui` | |
| `image` | the verified pin | v0.12.5, pinned by digest. Verify a new release under the `restricted-v2` SCC before changing it |
| `storageSize` | `10Gi` | Users, chats, uploads, the vector store and the seeded models |
| `storageClass` | cluster default | Set only to override the default StorageClass |
| `routeHost` | `<namespace>.<cluster ingress domain>` | Public hostname |
| `adminEmail` | | Strongly recommended. See [Administrator](#administrator) |
| `adminSecretRef.name` / `.key` | `open-webui-admin` / `password` | Secret holding the administrator password |

## Administrator

Open WebUI makes the first account to sign up the administrator. Without `adminEmail`, that is
whoever reaches the Route first.

With `adminEmail` set, Open WebUI creates the administrator at first start from a password in a
Secret that an administrator creates in the namespace, out of band:

```bash
oc create secret generic open-webui-admin -n open-webui --from-file=password=<file>
```

The pod does not start until that Secret exists, so the site is never reachable before its
administrator does. Open WebUI creates the account only while no user exists, so the setting is
safe to leave in place.

## Policies

| Policy | Mode | Does |
|--------|------|------|
| `policy-open-webui` | enforce | Namespace, the copied Hermes key, PVC, Deployment, Service and Route |
| `policy-open-webui-ready` | inform | The Deployment is Available, and the administrator Secret exists when `adminEmail` is set |

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
