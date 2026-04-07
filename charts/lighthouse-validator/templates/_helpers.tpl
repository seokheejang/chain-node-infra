{{/*
Chart name.
*/}}
{{- define "lighthouse-validator.name" -}}
{{- include "common.names.name" . }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "lighthouse-validator.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "lighthouse-validator.chart" -}}
{{- include "common.names.chart" . }}
{{- end }}

{{/*
Standard labels.
*/}}
{{- define "lighthouse-validator.labels" -}}
{{ include "common.labels.standard" . }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "lighthouse-validator.selectorLabels" -}}
{{ include "common.labels.matchLabels" . }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "lighthouse-validator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lighthouse-validator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
