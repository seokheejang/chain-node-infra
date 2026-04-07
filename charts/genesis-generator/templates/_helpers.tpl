{{/*
Chart name.
*/}}
{{- define "genesis-generator.name" -}}
{{- include "common.names.name" . }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "genesis-generator.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "genesis-generator.chart" -}}
{{- include "common.names.chart" . }}
{{- end }}

{{/*
Standard labels.
*/}}
{{- define "genesis-generator.labels" -}}
{{ include "common.labels.standard" . }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "genesis-generator.selectorLabels" -}}
{{ include "common.labels.matchLabels" . }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "genesis-generator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "genesis-generator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
