{{/*
Chart name.
*/}}
{{- define "lighthouse.name" -}}
{{- include "common.names.name" . }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "lighthouse.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "lighthouse.chart" -}}
{{- include "common.names.chart" . }}
{{- end }}

{{/*
Standard labels.
*/}}
{{- define "lighthouse.labels" -}}
{{ include "common.labels.standard" . }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "lighthouse.selectorLabels" -}}
{{ include "common.labels.matchLabels" . }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "lighthouse.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lighthouse.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
