{{/*
Get CloudCore image
*/}}
{{- define "kubeedge.cloudCoreImage" -}}
{{- $registry := .Values.cloudCore.image.registry | default .Values.global.imageRegistry }}
{{- $project := .Values.cloudCore.image.project }}
{{- $repository := .Values.cloudCore.image.repository }}
{{- $tag := .Values.cloudCore.image.tag | default .Chart.AppVersion }}
{{- if .Values.cloudCore.image.digest }}
{{- if $registry }}
{{- printf "%s/%s/%s@%s" $registry $project $repository .Values.cloudCore.image.digest }}
{{- else }}
{{- printf "%s/%s@%s" $project $repository .Values.cloudCore.image.digest }}
{{- end }}
{{- else }}
{{- if $registry }}
{{- printf "%s/%s/%s:%s" $registry $project $repository $tag }}
{{- else }}
{{- printf "%s/%s:%s" $project $repository $tag }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Get IPTables Manager image
*/}}
{{- define "kubeedge.iptablesImage" -}}
{{- $registry := .Values.iptablesManager.image.registry | default .Values.global.imageRegistry }}
{{- $project := .Values.iptablesManager.image.project }}
{{- $repository := .Values.iptablesManager.image.repository }}
{{- $tag := .Values.iptablesManager.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s/%s:%s" $registry $project $repository $tag }}
{{- else }}
{{- printf "%s/%s:%s" $project $repository $tag }}
{{- end }}
{{- end }}

{{/*
Get Mosquitto image
*/}}
{{- define "kubeedge.mosquittoImage" -}}
{{- $registry := .Values.mosquitto.image.registry | default .Values.global.imageRegistry }}
{{- $project := .Values.mosquitto.image.project }}
{{- $repository := .Values.mosquitto.image.repository }}
{{- $tag := .Values.mosquitto.image.tag }}
{{- if $registry }}
{{- printf "%s/%s/%s:%s" $registry $project $repository $tag }}
{{- else }}
{{- printf "%s/%s:%s" $project $repository $tag }}
{{- end }}
{{- end }}

{{/*
Image pull secrets
*/}}
{{- define "kubeedge.imagePullSecrets" -}}
{{- $secrets := list }}
{{- range .Values.global.imagePullSecrets }}
{{- $secrets = append $secrets . }}
{{- end }}
{{- range .Values.cloudCore.image.pullSecrets }}
{{- $secrets = append $secrets . }}
{{- end }}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets | uniq }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}
