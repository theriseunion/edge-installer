{{/*
Expand the name of the chart.
*/}}
{{- define "traefik.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "traefik.fullname" -}}
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
{{- define "traefik.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "traefik.labels" -}}
helm.sh/chart: {{ include "traefik.chart" . }}
{{ include "traefik.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "traefik.selectorLabels" -}}
app.kubernetes.io/name: {{ include "traefik.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: traefik
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "traefik.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "traefik.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get namespace
*/}}
{{- define "traefik.namespace" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}

{{/*
Generate Traefik TLS certificates (self-signed)
This generates a CA and signs a certificate for Traefik
*/}}
{{- define "traefik.genCerts" -}}
{{- $altNames := list }}
{{- $altNames = append $altNames "*.local" }}
{{- $altNames = append $altNames "*.vcluster.local" }}
{{- $altNames = append $altNames (printf "traefik.%s.svc.cluster.local" (include "traefik.namespace" .)) }}
{{- $altNames = append $altNames (printf "traefik.%s.svc" (include "traefik.namespace" .)) }}
{{- $altNames = append $altNames "traefik" }}
{{- $altNames = append $altNames "localhost" }}

{{- $altIPs := list }}
{{- $altIPs = append $altIPs "127.0.0.1" }}
{{- $altIPs = append $altIPs "192.168.0.143" }}

{{- $ca := genCA "Traefik CA" 3650 }}
{{- $cert := genSignedCert "*.local" $altIPs $altNames 3650 $ca }}

tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
ca.crt: {{ $ca.Cert | b64enc }}
{{- end }}

{{/*
Get the image registry
*/}}
{{- define "traefik.imageRegistry" -}}
{{- $registry := .Values.traefik.image.registry | default .Values.global.imageRegistry | default "" -}}
{{- if $registry -}}
{{- printf "%s/" $registry -}}
{{- end -}}
{{- end }}

{{/*
Get the full image name
*/}}
{{- define "traefik.image" -}}
{{- $registry := include "traefik.imageRegistry" . -}}
{{- $repository := .Values.traefik.image.repository -}}
{{- $tag := .Values.traefik.image.tag | default .Chart.AppVersion -}}
{{- printf "%s%s:%s" $registry $repository $tag -}}
{{- end }}
