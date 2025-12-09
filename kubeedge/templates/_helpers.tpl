{{/*
Expand the name of the chart.
*/}}
{{- define "kubeedge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "kubeedge.fullname" -}}
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
{{- define "kubeedge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kubeedge.labels" -}}
helm.sh/chart: {{ include "kubeedge.chart" . }}
{{ include "kubeedge.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kubeedge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeedge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CloudCore specific labels
*/}}
{{- define "kubeedge.cloudcore.labels" -}}
k8s-app: kubeedge
kubeedge: cloudcore
{{- end }}

{{/*
IPTables Manager specific labels
*/}}
{{- define "kubeedge.iptables.labels" -}}
k8s-app: iptables-manager
kubeedge: iptables-manager
{{- end }}

{{/*
Mosquitto specific labels
*/}}
{{- define "kubeedge.mosquitto.labels" -}}
k8s-app: eclipse-mosquitto
kubeedge: eclipse-mosquitto
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kubeedge.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default "cloudcore" .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate CloudCore certificates
*/}}
{{- define "kubeedge.genCloudCoreCerts" -}}
{{- $altNames := list }}
{{- $altNames = append $altNames (printf "cloudcore.%s.svc.cluster.local" .Release.Namespace) }}
{{- $altNames = append $altNames (printf "cloudcore.%s.svc" .Release.Namespace) }}
{{- $altNames = append $altNames "cloudcore.kubeedge" }}
{{- $altNames = append $altNames "cloudcore.kubeedge.svc" }}
{{- $altNames = append $altNames "cloudcore" }}

{{- $ca := genCA "cloudcore-ca" 3650 }}
{{- $cert := genSignedCert "cloudcore" nil $altNames 3650 $ca }}

streamCA.crt: {{ $ca.Cert | b64enc }}
stream.crt: {{ $cert.Cert | b64enc }}
stream.key: {{ $cert.Key | b64enc }}
{{- end }}

{{/*
Get namespace
*/}}
{{- define "kubeedge.namespace" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}
