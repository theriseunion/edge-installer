{{- define "syncer.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.syncer.image -}}
{{- else -}}
{{- printf "%s" .Values.syncer.image -}}
{{- end -}}
{{- end -}}

{{- define "vcluster.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.vcluster.image -}}
{{- else -}}
{{- printf "%s" .Values.vcluster.image -}}
{{- end -}}
{{- end -}}

{{- define "coredns.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.coredns.image -}}
{{- else -}}
{{- printf "%s" .Values.coredns.image -}}
{{- end -}}
{{- end -}}

{{- define "api.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.api.image -}}
{{- else -}}
{{- printf "%s" .Values.api.image -}}
{{- end -}}
{{- end -}}

{{- define "controller.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.controller.image -}}
{{- else -}}
{{- printf "%s" .Values.controller.image -}}
{{- end -}}
{{- end -}}

{{- define "scheduler.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.scheduler.image -}}
{{- else -}}
{{- printf "%s" .Values.scheduler.image -}}
{{- end -}}
{{- end -}}

{{- define "etcd.image" -}}
{{- $registryName := "" -}}
{{- if and .Values.global.imageRegistry (ne (.Values.global.imageRegistry | default "") "docker.io") -}}
{{- $registryName = .Values.global.imageRegistry -}}
{{- printf "%s/%s" $registryName .Values.etcd.image -}}
{{- else -}}
{{- printf "%s" .Values.etcd.image -}}
{{- end -}}
{{- end -}}