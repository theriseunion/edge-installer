{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "duty.backend.fullname" -}}
{{- if .Values.backend.fullnameOverride }}
  {{- .Values.backend.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
  {{- $component := default "backend" .Values.backend.componentName }}
  {{- $name := default .Chart.Name .Values.nameOverride }}
  {{- if .Values.backend.nameOverride }}
    {{- $name = .Values.backend.nameOverride }}
  {{- end }}
  {{- if contains $component .Release.Name }}
    {{- .Release.Name | trunc 63 | trimSuffix "-" }}
  {{- else }}
    {{- printf "%s-%s" .Release.Name $component | trunc 63 | trimSuffix "-" }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "duty.frontend.fullname" -}}
{{- if .Values.frontend.fullnameOverride }}
  {{- .Values.frontend.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
  {{- $component := default "console-ui" .Values.frontend.componentName }}  {{/* 组件名默认 console-ui，可自定义 */}}
  {{- $name := default "console-ui" .Values.frontend.nameOverride }}        {{/* 前端单独的 nameOverride，不依赖 Chart 名 */}}
  {{- /* 拼接规则：发布名 + 组件名（若发布名已包含组件名，则直接用发布名） */}}
  {{- if contains $component .Release.Name }}
    {{- .Release.Name | trunc 63 | trimSuffix "-" }}
  {{- else }}
    {{- printf "%s-%s" .Release.Name $component | trunc 63 | trimSuffix "-" }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "duty.chart" -}}
{{- .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "duty.labels" -}}
helm.sh/chart: {{ include "duty.chart" . }}
{{ include "duty.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "duty.selectorLabels" -}}
app.kubernetes.io/name: {{ include "duty.backend.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "duty.serviceAccountName" -}}
{{- if .Values.duty.serviceAccount.create -}}
  {{- default (include "duty.backend.fullname" .) .Values.duty.serviceAccount.name -}}
{{- else -}}
  {{- default "default" .Values.duty.serviceAccount.name -}}
{{- end -}}
{{- end -}}

