{{/*
Expand the name of the chart.
*/}}
{{- define "openyurt-addition.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "openyurt-addition.fullname" -}}
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
{{- define "openyurt-addition.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openyurt-addition.labels" -}}
helm.sh/chart: {{ include "openyurt-addition.chart" . }}
{{ include "openyurt-addition.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openyurt-addition.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openyurt-addition.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the proper image name for kube-proxy
*/}}
{{- define "openyurt-addition.kubeProxyImage" -}}
{{- $registry := .Values.kubeProxy.image.registry | default .Values.global.imageRegistry }}
{{- $repository := .Values.kubeProxy.image.repository }}
{{- $tag := .Values.kubeProxy.image.tag | default .Values.global.tag }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Return the proper image name for coredns
*/}}
{{- define "openyurt-addition.corednsImage" -}}
{{- $registry := .Values.coredns.image.registry | default .Values.global.imageRegistry }}
{{- $repository := .Values.coredns.image.repository }}
{{- $tag := .Values.coredns.image.tag | default .Values.global.tag }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Return the proper image name for nodelocaldns
*/}}
{{- define "openyurt-addition.nodelocaldnsImage" -}}
{{- $registry := .Values.nodelocaldns.image.registry | default .Values.global.imageRegistry }}
{{- $repository := .Values.nodelocaldns.image.repository }}
{{- $tag := .Values.nodelocaldns.image.tag | default .Values.global.tag }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}
