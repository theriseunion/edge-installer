{{/*
Expand the name of the chart.
*/}}
{{- define "apiserver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "apiserver.fullname" -}}
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
{{- define "apiserver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "apiserver.labels" -}}
helm.sh/chart: {{ include "apiserver.chart" . }}
{{ include "apiserver.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: apiserver-project
{{- end }}

{{/*
Selector labels
*/}}
{{- define "apiserver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apiserver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: apiserver
component: apiserver
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "apiserver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "apiserver.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create namespace
*/}}
{{- define "apiserver.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else if and .Values.global .Values.global.namespaceOverride }}
{{- .Values.global.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Create certificate secret name
*/}}
{{- define "apiserver.certSecretName" -}}
{{- if .Values.cert.secretName }}
{{- .Values.cert.secretName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-cert" (include "apiserver.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Check if cert-manager is enabled
*/}}
{{- define "apiserver.certManagerEnabled" -}}
{{- $enabled := false }}
{{- if hasKey .Values "cert-manager" }}
  {{- if hasKey (index .Values "cert-manager") "enabled" }}
    {{- $enabled = index .Values "cert-manager" "enabled" }}
  {{- end }}
{{- else if and .Root (hasKey .Root.Values "cert-manager") }}
  {{- if hasKey (index .Root.Values "cert-manager") "enabled" }}
    {{- $enabled = index .Root.Values "cert-manager" "enabled" }}
  {{- end }}
{{- end }}
{{- if $enabled }}true{{- else }}false{{- end }}
{{- end }}

{{/*
Generate APIServer TLS certificates (deprecated - use cert-manager instead)
*/}}
{{- define "apiserver.genCerts" -}}
{{- $fullName := include "apiserver.fullname" . }}
{{- $namespace := include "apiserver.namespace" . }}
{{- $altNames := list }}
{{- $altNames = append $altNames (printf "%s.%s.svc.cluster.local" $fullName $namespace) }}
{{- $altNames = append $altNames (printf "%s.%s.svc" $fullName $namespace) }}
{{- $altNames = append $altNames $fullName }}
{{- $altNames = append $altNames "127.0.0.1" }}
{{- $altNames = append $altNames "localhost" }}
{{- range .Values.cert.additionalHosts }}
{{- $altNames = append $altNames . }}
{{- end }}

{{- $validityDays := int (.Values.cert.validityDays | default 3650) }}
{{- $ca := genCA (printf "%s-ca" $fullName) $validityDays }}
{{- $cert := genSignedCert $fullName nil $altNames $validityDays $ca }}

tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
ca.crt: {{ $ca.Cert | b64enc }}
{{- end }}

{{/*
Get CA bundle from cert-manager Certificate secret for ReverseProxy
This function attempts to lookup the CA certificate from the Secret created by cert-manager.
If the Secret doesn't exist yet (e.g., during initial deployment), it returns an empty string.
Users can also manually set cert.reverseProxy.caBundle in values.yaml as a fallback.
*/}}
{{- define "apiserver.caBundle" -}}
{{- $caBundle := "" }}
{{- if and .Values.enabled .Values.config.server.tls.enabled }}
  {{- if eq (include "apiserver.certManagerEnabled" .) "true" }}
    {{- /* Try to get CA bundle from values.yaml first (manual override) */}}
    {{- if and .Values.cert .Values.cert.reverseProxy .Values.cert.reverseProxy.caBundle }}
      {{- $caBundle = .Values.cert.reverseProxy.caBundle }}
    {{- else }}
      {{- /* Try to lookup the Secret created by cert-manager */}}
      {{- $secretName := include "apiserver.certSecretName" . }}
      {{- $namespace := include "apiserver.namespace" . }}
      {{- $secret := lookup "v1" "Secret" $namespace $secretName }}
      {{- if and $secret $secret.data }}
        {{- if hasKey $secret.data "ca.crt" }}
          {{- $caBundle = index $secret.data "ca.crt" }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $caBundle }}
{{- end }}

