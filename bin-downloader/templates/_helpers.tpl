{{/*
Expand the name of the chart.
*/}}
{{- define "bin-downloader.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "bin-downloader.fullname" -}}
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
{{- define "bin-downloader.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "bin-downloader.labels" -}}
helm.sh/chart: {{ include "bin-downloader.chart" . }}
{{ include "bin-downloader.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bin-downloader.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bin-downloader.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: bin-downloader
{{- end }}

{{/*
Get namespace - use Release.Namespace, default to edge-system
*/}}
{{- define "bin-downloader.namespace" -}}
{{- default "edge-system" .Release.Namespace }}
{{- end }}

{{/*
Get the image registry
*/}}
{{- define "bin-downloader.imageRegistry" -}}
{{- $registry := .Values.image.registry | default .Values.global.imageRegistry | default "" -}}
{{- if $registry -}}
{{- printf "%s/" $registry -}}
{{- end -}}
{{- end }}

{{/*
Get the full image name
*/}}
{{- define "bin-downloader.image" -}}
{{- $registry := include "bin-downloader.imageRegistry" . -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s%s:%s" $registry $repository $tag -}}
{{- end }}
