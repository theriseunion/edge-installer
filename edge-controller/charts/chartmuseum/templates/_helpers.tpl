{{/*
Expand the name of the chart.
*/}}
{{- define "chartmuseum.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We use the parent chart's fullname to maintain naming consistency.
*/}}
{{- define "chartmuseum.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chartmuseum.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chartmuseum.labels" -}}
helm.sh/chart: {{ include "chartmuseum.chart" . }}
{{ include "chartmuseum.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: chartmuseum
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chartmuseum.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chartmuseum.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
