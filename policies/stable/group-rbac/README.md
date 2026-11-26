# group-rbac

Binds identity-provider groups to cluster and namespace roles. It creates no
Group objects, touches no identity provider, and needs no htpasswd Secret.

The use it was written for is a cluster whose users sign in through an external
OIDC provider with OpenShift direct authentication. That cluster has no
`user.openshift.io` API, so the `htpasswd-users` policy cannot run: there is no
Group object to declare and no HTPasswd identity provider to add. Group
membership still reaches the API server - in the token's `groups` claim - and
RBAC binds to those group names directly. This policy does only the bindings.

## Configuration

Enablement label `autoshift.io/group-rbac`, plus `config.group-rbac`:

```yaml
config:
  group-rbac:
    groups:
      - name: cluster-admins
        clusterRoles:
          - cluster-admin
      - name: maas-users
        namespaceRoles:
          - namespace: llm
            role: view
```

| Key | Default | Notes |
|---|---|---|
| `groups` | | required; with no entries the policy fails rather than rendering nothing |
| `groups[].name` | | required; matches the group name in the token's `groups` claim |
| `groups[].clusterRoles` | `[]` | ClusterRole names, bound cluster-wide |
| `groups[].namespaceRoles` | `[]` | RoleBindings to a ClusterRole, per namespace |

Every group needs a `name` and at least one role: an entry with neither
`clusterRoles` nor `namespaceRoles` is a mistake, not an empty group, and the
policy fails naming it. A `role` in `namespaceRoles` is a ClusterRole bound
inside that one namespace, as `htpasswd-users` does it.

The sample groups and namespace are examples. Use your own.

The policy fails, and names the problem, when `config.group-rbac` is missing
or empty, when a group has no `name`, when a group has neither
`clusterRoles` nor `namespaceRoles`, or when a `namespaceRoles` entry lacks
`namespace` or `role`.

## What it creates

One ClusterRoleBinding per `clusterRoles` entry and one RoleBinding per
`namespaceRoles` entry, each with a single subject of `kind: Group`. The API
server resolves the subject against the `groups` claim of the token, so the
binding works the moment a member signs in - no Group object is needed.

A RoleBinding into a namespace that does not exist yet reports NonCompliant
until that namespace appears, then reconciles on its own.

## How it differs from htpasswd-users

`htpasswd-users` adds an HTPasswd identity provider, declares `user.openshift.io`
Group objects, and binds roles to them. This policy binds the same shapes of
role to the same shapes of group name and stops there.

The two policies name their bindings differently - `htpasswd-<group>-<role>`
against `group-rbac-<group>-<role>` - so installing both does not corrupt
either. Use one or the other for the same group names all the same: two
policies binding the same group to different roles is a configuration mistake
this policy cannot see.

## Verifying

```bash
oc get clusterrolebindings.rbac.authorization.k8s.io | grep group-rbac-
oc get rolebindings.rbac.authorization.k8s.io -A | grep group-rbac-
```

`policy-group-rbac-ready` is an inform-only companion that asserts each
expected binding exists on the cluster, so a binding deleted by hand is named
per group and role rather than showing up as generic drift in the enforcing
policy.

## Turning it off

The policy runs with `pruneObjectBehavior: None`: setting the label to
`'false'` stops reconciliation and leaves the bindings in place. Removing
bindings is a deliberate act - delete them by hand once nobody uses them.
