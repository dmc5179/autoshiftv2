# Vendored OpenShell Helm chart

`helm-chart/` is NVIDIA's OpenShell Helm chart, copied into the repository so the hub renders the
`openshell` policy with no network access. A disconnected hub needs this: the hub's OpenShift GitOps
repository server renders the chart itself, and Helm ignores the cluster's `ImageDigestMirrorSet`
and `ImageTagMirrorSet`, so mirroring the chart does not let it pull one.
`../manifests/chart/kustomization.yaml` points kustomize at it through `helmGlobals.chartHome`.

## Provenance

| | |
|---|---|
| Source | `oci://ghcr.io/nvidia/openshell/helm-chart` |
| Version | `0.1.6` (`version` and `appVersion` in `helm-chart/Chart.yaml`) |
| OCI manifest digest | `sha256:036f3fe3b0ef9603c2b43ab8e32ddfaeb101f1e5041109017681bf5d61e7a7b5` |
| Chart archive (`helm-chart-0.1.6.tgz`) sha256 | `0533ecf84f777954aaf6113a0813fbc9781ed2a5e6574fb807cebe9a818a1bd4` |
| Upstream release | <https://github.com/NVIDIA/OpenShell/releases/tag/v0.1.6> |
| Licence | Apache-2.0. The packaged chart carries no licence file; every template has an `SPDX-License-Identifier: Apache-2.0` header, and `LICENSE` here is the repository's licence at tag `v0.1.6`. Upstream has no `NOTICE` file |

## What was copied

Exactly the files Helm reads to render the chart, unmodified: `Chart.yaml`, `values.yaml`,
`.helmignore` and `templates/`. Two parts of the published archive are left out because nothing
here reads them:

- `README.md`, the chart's own documentation. Every Markdown file under `policies/` is linted
  with the Red Hat prose style, which upstream text is not written to. Read it upstream.
- `tests/`, the chart's helm-unittest suites and fixtures. `helm template` never loads them.

The render is identical to the one from the OCI registry: both outputs of
`../manifests/chart/kustomization.yaml` (through `../manifests/gateway` and
`../manifests/statefulset`) and the rendered policy compare byte for byte.

## Updating

Move the chart and the image tag together. Each Red Hat `v<version>-rhaiv.N` build is made from one
upstream release, and a tag from another release can fail against this chart's `gateway.toml`.

```shell
VERSION=0.1.7                                    # the new chart version
cd policies/community/openshell
helm pull oci://ghcr.io/nvidia/openshell/helm-chart --version "${VERSION}" -d /tmp/openshell-chart
sha256sum "/tmp/openshell-chart/helm-chart-${VERSION}.tgz"
tar -xzf "/tmp/openshell-chart/helm-chart-${VERSION}.tgz" -C /tmp/openshell-chart
rm -rf vendor/helm-chart && mkdir vendor/helm-chart
cp -r /tmp/openshell-chart/helm-chart/{Chart.yaml,values.yaml,.helmignore,templates} vendor/helm-chart/
curl -sSfo vendor/LICENSE "https://raw.githubusercontent.com/NVIDIA/OpenShell/v${VERSION}/LICENSE"
```

Then:

1. Update the table above: the version, the OCI manifest digest that `helm pull` prints, and the
   archive sha256.
2. Set `version:` in `../manifests/chart/kustomization.yaml`. kustomize does not check it for a
   local chart, so it is for readers.
3. Move `autoshift.io/openshell-version` in the values files, and its `_example.yaml` samples, to
   the matching `v<version>-rhaiv.N` build, and the chart and image entries in the disconnected
   imagesets.
4. Render both overlays, compare them with the previous output, and read every difference. Patches
   in `../manifests/chart/kustomization.yaml` target fields by path, and a chart change can move or
   remove one. A JSON patch `remove` then fails the render, which is the intended signal.
5. Run `make test`.

```shell
for o in gateway statefulset; do
  (cd manifests/$o && kustomize build --enable-helm --load-restrictor LoadRestrictionsNone .)
done
```
