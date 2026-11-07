# htpasswd-users

Adds an HTPasswd identity provider to the cluster, declares Groups of those
users, and binds roles to each Group.

The use it was written for is Models-as-a-Service. A MaaS subscription is owned
by Groups, and a person can mint an API key only if they belong to one. A
cluster installed with only `kubeadmin` has no Group a person can join, so
without this policy every MaaS key is minted either by `kubeadmin` or by a
ServiceAccount.

## Configuration

Enablement label `autoshift.io/htpasswd-users`, plus `config.htpasswdUsers`:

```yaml
config:
  htpasswdUsers:
    providerName: htpasswd          # the name shown on the login page
    secretName: htpasswd-users      # in openshift-config; created out of band
    groups:
      - name: maas-users
        users:
          - maas-user
        clusterRoles: []            # ClusterRoleBindings, by ClusterRole name
        namespaceRoles:             # RoleBindings to a ClusterRole, per namespace
          - namespace: llm
            role: view
```

| Key | Default | Notes |
|---|---|---|
| `providerName` | `htpasswd` | Do not change in place; see below |
| `secretName` | `htpasswd-users` | Do not change in place; see below |
| `groups` | `[]` | optional; with none, the policy adds only the identity provider |
| `groups[].name` | | required |
| `groups[].users` | `[]` | user names, matching the names in the htpasswd file |
| `groups[].clusterRoles` | `[]` | |
| `groups[].namespaceRoles` | `[]` | each entry needs both `namespace` and `role` |

The sample group, user and namespace are examples. Use your own.

The policy fails, and names the problem, when `config.htpasswdUsers` is missing, when a group has
no `name`, or when a `namespaceRoles` entry lacks `namespace` or `role`. It also fails when the
cluster's rendered-config ConfigMap is missing, rather than applying defaults to a cluster whose
configuration never arrived.

## The password never comes from Git

The htpasswd Secret holds password hashes, which do not belong in a
repository even hashed. It is created out of band, with the htpasswd file
under the key `htpasswd`:

```bash
htpasswd -c -B -b users.htpasswd maas-user '<password>'
oc create secret generic htpasswd-users -n openshift-config \
  --from-file=htpasswd=users.htpasswd
```

The policy adds the identity provider **only once that Secret exists**.
Pointing OAuth at a missing Secret degrades the authentication operator, so
until the Secret appears this policy adds nothing to OAuth. Order does not
matter: create the Secret before or after enabling the policy.

## What it creates

| | |
|---|---|
| `policy-htpasswd-users` | the OAuth identity provider entry, each `Group`, and its role bindings |
| `policy-htpasswd-users-ready` | inform-only: the Secret exists, OAuth carries the provider, and the authentication operator is Available and not Degraded |

## Why the readiness policy checks the authentication operator

A provider pointing at a malformed Secret is accepted by the API server. The
OAuth object looks correct and the enforcing policy reports Compliant. The
failure surfaces only on the authentication ClusterOperator, as Degraded, and
as logins that fail. Asserting on the operator is what turns that into a
visible NonCompliant.

## OAuth is shared, so this policy merges rather than owns

`OAuth/cluster` is a singleton holding every identity provider on the cluster.
This policy writes its entry with `complianceType: musthave`, which merges into
the existing list. `mustonlyhave` would replace the whole list with this one
entry and could lock out every other user.

The cost of merging into a list: changing `providerName` or `secretName` in
place appends a second entry rather than replacing the first. Two providers
with the same name degrade the authentication operator. To rename, remove the
old entry from `OAuth/cluster` by hand first. See
[policy-behavior.md](../../../docs/policy-behavior.md).

## Groups are owned outright

Each `Group` uses `mustonlyhave`, since `users` is a list. Removing a user from
config removes them from the live Group.

That does **not** revoke MaaS API keys they already minted. Per the RHOAI 3.5
Models-as-a-Service documentation, keys must be revoked by hand when a user
leaves a group.

## RBAC is opt-in

No role is bound by default. Minting a MaaS key needs no Kubernetes RBAC:
MaaS checks only that the caller's Groups appear in the subscription's
`owner.groups` and the auth policy's `subjects.groups`. Bind roles only for
what a person does beyond calling models, such as viewing the model
deployment.

A RoleBinding into a namespace that does not exist yet reports NonCompliant
until the namespace appears, then reconciles without intervention.

## Turning it off

`pruneObjectBehavior: None`. Disabling the policy leaves the provider, Groups
and bindings in place, since people may be using them. Remove them by hand.
