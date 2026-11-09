{{/*
Validate that the openshell labels come with what their policies depend on.

The openshell policies depend on other policies on the SAME cluster: an ACM dependency resolves
against that cluster's own copy of the named policy, so where the other policy is not placed there
is no copy to satisfy it, and the openshell policies stay Pending with nothing explaining why. Fail
the render instead.

  openshell       needs agent-sandbox and cert-manager (policy-openshell-prereqs)
  openshell-maas  needs openshell, openshift-ai-maas and openshift-ai-models
                  (policy-openshell-maas-provider), and config.openshell.maas.model

Labels resolve the way cluster-labels merges them, the cluster's own value then its clusterset's.
Config resolves the way rendered-config merges it: the cluster's, its clusterset's, then global.
*/}}
{{- define "autoshift.validate-openshell" -}}
{{- $requires := dict
      "openshell" (list "agent-sandbox" "cert-manager")
      "openshell-maas" (list "openshell" "openshift-ai-maas" "openshift-ai-models") }}
{{- $globalModel := (dig "openshell" "maas" "model" "" (.Values.config | default dict)) }}
{{- $errors := list }}
{{- $targets := list }}
{{- $clusterSets := dict }}
{{- range $bucket := list "hubClusterSets" "managedClusterSets" }}
  {{- range $name, $cs := (index $.Values $bucket | default dict) }}
    {{- $_ := set $clusterSets $name $cs }}
    {{- $model := (dig "config" "openshell" "maas" "model" "" $cs) | default $globalModel }}
    {{- $targets = append $targets (dict "path" (printf "%s.%s" $bucket $name) "labels" ($cs.labels | default dict) "model" $model) }}
  {{- end }}
{{- end }}
{{- range $name, $cluster := (.Values.clusters | default dict) }}
  {{- $cs := (index $clusterSets (dig "config" "clusterSet" "" $cluster) | default dict) }}
  {{- $labels := merge (deepCopy ($cluster.labels | default dict)) ($cs.labels | default dict) }}
  {{- $model := (dig "config" "openshell" "maas" "model" "" $cluster) | default (dig "config" "openshell" "maas" "model" "" $cs) | default $globalModel }}
  {{- $targets = append $targets (dict "path" (printf "clusters.%s" $name) "labels" $labels "model" $model) }}
{{- end }}

{{- range $t := $targets }}
  {{- range $label, $needs := $requires }}
    {{- if eq (toString (index $t.labels $label | default "false")) "true" }}
      {{- range $req := $needs }}
        {{- if ne (toString (index $t.labels $req | default "false")) "true" }}
          {{- $errors = append $errors (printf "%s: %s is 'true' but %s is not" $t.path $label $req) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if and (eq (toString (index $t.labels "openshell-maas" | default "false")) "true") (not $t.model) }}
    {{- $errors = append $errors (printf "%s: openshell-maas is 'true' but config.openshell.maas.model is not set in its own, its clusterset's or the global config" $t.path) }}
  {{- end }}
{{- end }}

{{- if gt (len $errors) 0 }}
  {{- fail (printf "\n\nOpenShell validation failed (%d errors):\n  - %s\n\nThe openshell policies depend on other policies on the same cluster, and stay Pending without them.\nopenshell needs agent-sandbox and cert-manager. openshell-maas needs openshell, openshift-ai-maas,\nopenshift-ai-models and config.openshell.maas.model.\n" (len $errors) (join "\n  - " $errors)) }}
{{- end }}
{{- end -}}
