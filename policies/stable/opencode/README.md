# opencode

Adds an "OpenCode (MaaS)" sample to the Red Hat OpenShift Dev Spaces dashboard. The sample opens [devfile/devfile.yaml](devfile/devfile.yaml), which runs OpenCode in the editor terminal of the user's own workspace against Red Hat OpenShift AI Models-as-a-Service (MaaS). `policy-opencode-samples` creates three ConfigMaps in `openshift-devspaces`: the sample, the MaaS URL and model as environment variables for every workspace, and the ingress CA for the workspace trust bundle.

**Enable it.** Set `opencode: 'true'` next to `dev-spaces: 'true'`. The Placement requires both labels. Then set `config.opencode.model` to a model in `config.openshiftAiModels.models`. `devfileUrl`, `displayName` and `maasHost` are optional. The policy waits for `policy-devspaces-ready-test`.

**One-time step for each user.** The user must be in a group the model's `accessGroups` grants, such as `maas-users`. Mint a key in the Red Hat OpenShift AI dashboard, or with the user's own token:

```bash
KEY=$(curl -sk -X POST "https://maas.<apps domain>/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" -H 'Content-Type: application/json' \
  -d '{"name":"opencode"}' | jq -r .key)
oc create secret generic maas-api-key -n <user>-devspaces --from-literal=MAAS_API_KEY="$KEY"
oc label secret maas-api-key -n <user>-devspaces \
  controller.devfile.io/mount-to-devworkspace=true controller.devfile.io/watch-secret=true
oc annotate secret maas-api-key -n <user>-devspaces controller.devfile.io/mount-as=env
```

The key is then an environment variable in every workspace the user starts. Restart a workspace that is already running.

**Use it.** Open the sample from the dashboard. When the workspace is up, open a terminal and run `cd /projects/workspace && opencode`, or run the **Start OpenCode** task. The workspace writes the OpenCode configuration at start-up; its log is `/tmp/opencode-setup.log`.

**Authentication.** OpenCode runs in the terminal, and the devfile exposes no endpoint, so the Dev Spaces sign-in that protects the editor protects OpenCode too. To sign in with Keycloak later, configure Dev Spaces for an external identity provider, and change nothing here.

**Why not the OpenCode web UI.** It loads its assets from absolute paths, so it renders blank behind the Dev Spaces path-based gateway. On its own host name, Dev Spaces routes it without authentication. It also listens on every interface with no password.
