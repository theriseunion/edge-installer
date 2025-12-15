{{/*
Expand the name of the chart.
*/}}
{{- define "controller.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "controller.fullname" -}}
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
{{- define "controller.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "controller.labels" -}}
helm.sh/chart: {{ include "controller.chart" . }}
{{ include "controller.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: apiserver-project
{{- end }}

{{/*
Selector labels
*/}}
{{- define "controller.selectorLabels" -}}
app.kubernetes.io/name: {{ include "controller.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
control-plane: controller-manager
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "controller.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "controller.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create namespace
*/}}
{{- define "controller.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else if and .Values.global .Values.global.namespaceOverride }}
{{- .Values.global.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Create webhook service name
*/}}
{{- define "controller.webhook.serviceName" -}}
{{- if .Values.webhook.service.name }}
{{- .Values.webhook.service.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-webhook-service" (include "controller.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create webhook certificate secret name
*/}}
{{- define "controller.webhook.certSecretName" -}}
{{- if .Values.webhook.cert.secretName }}
{{- .Values.webhook.cert.secretName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-webhook-cert" (include "controller.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create webhook certificate directory
*/}}
{{- define "controller.webhook.certDir" -}}
{{- .Values.webhook.server.certDir | default "/tmp/k8s-webhook-server/serving-certs" }}
{{- end }}

{{/*
Generate Controller Webhook TLS certificates
*/}}
{{- define "controller.webhook.genCerts" -}}
{{- $fullName := include "controller.fullname" . }}
{{- $namespace := include "controller.namespace" . }}
{{- $serviceName := include "controller.webhook.serviceName" . }}
{{- $altNames := list }}
{{- $altNames = append $altNames (printf "%s.%s.svc.cluster.local" $serviceName $namespace) }}
{{- $altNames = append $altNames (printf "%s.%s.svc" $serviceName $namespace) }}
{{- $altNames = append $altNames $serviceName }}
{{- $altNames = append $altNames "127.0.0.1" }}
{{- $altNames = append $altNames "localhost" }}
{{- range .Values.webhook.cert.additionalHosts }}
{{- $altNames = append $altNames . }}
{{- end }}

{{- $validityDays := int (.Values.webhook.cert.validityDays | default 3650) }}
{{- $ca := genCA (printf "%s-webhook-ca" $fullName) $validityDays }}
{{- $cert := genSignedCert (printf "%s-webhook" $fullName) nil $altNames $validityDays $ca }}

tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
ca.crt: {{ $ca.Cert | b64enc }}
ca: {{ $ca.Cert | b64enc }}
{{- end }}

{{/*
Generate Controller Webhook CA Bundle for webhook configuration
*/}}
{{- define "controller.webhook.caBundle" -}}
{{- if and .Values.webhook.enabled .Values.webhook.cert.create }}
{{- $fullName := include "controller.fullname" . }}
{{- $validityDays := int (.Values.webhook.cert.validityDays | default 3650) }}
{{- $ca := genCA (printf "%s-webhook-ca" $fullName) $validityDays }}
{{- $ca.Cert | b64enc }}
{{- end }}
{{- end }}

