{{/*
Expand the name of the chart.
*/}}
{{- define "edge-ota.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "edge-ota.fullname" -}}
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
{{- define "edge-ota.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "edge-ota.labels" -}}
helm.sh/chart: {{ include "edge-ota.chart" . }}
{{ include "edge-ota.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: edge-ota
{{- end }}

{{/*
Selector labels
*/}}
{{- define "edge-ota.selectorLabels" -}}
app.kubernetes.io/name: {{ include "edge-ota.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "edge-ota.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "edge-ota.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the namespace
*/}}
{{- define "edge-ota.namespace" -}}
{{- if .Values.namespace.name }}
{{- .Values.namespace.name }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Get NATS URL - either from subchart or external
*/}}
{{- define "edge-ota.natsUrl" -}}
{{- if .Values.nats.enabled }}
{{- printf "nats://nats.%s.svc.cluster.local:4222" (include "edge-ota.namespace" .) }}
{{- else }}
{{- .Values.nats.externalUrl }}
{{- end }}
{{- end }}

{{/*
Get image reference
*/}}
{{- define "edge-ota.image" -}}
{{- $registry := default .Values.image.registry .Values.global.imageRegistry }}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry .Values.image.repository $tag }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}
{{- end }}
