{{/*
Chart name.
*/}}
{{- define "geth.name" -}}
{{- include "common.names.name" . }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "geth.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "geth.chart" -}}
{{- include "common.names.chart" . }}
{{- end }}

{{/*
Standard labels.
*/}}
{{- define "geth.labels" -}}
{{ include "common.labels.standard" . }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "geth.selectorLabels" -}}
{{ include "common.labels.matchLabels" . }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "geth.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "geth.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
