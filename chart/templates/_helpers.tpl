# Copyright 2022-2026 The MathWorks, Inc.
{{/*
Expand the name of the chart.
*/}}
{{- define "webapps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "webapps.fullname" -}}
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
{{- define "webapps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "webapps.labels" -}}
helm.sh/chart: {{ include "webapps.chart" . }}
{{ include "webapps.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "webapps.selectorLabels" -}}
app.kubernetes.io/name: {{ include "webapps.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Docker image for server
*/}}
{{- define "webapps.serverImage" -}}
{{- printf "%s:%s" .Values.images.serverName (default (.Values.internal.serverRelease | lower) .Values.images.serverTag) }}
{{- end }}

{{/*
Docker image for worker with tag (non-embedded case)
*/}}
{{- define "webapps.workerImage" -}}
{{- printf "%s:%s" (include "webapps.workerImageName" .) (include "webapps.workerImageTag" .) }}
{{- end }}

{{- define "webapps.workerImageName" -}}
{{- .Values.images.workerName }}
{{- end }}

{{- define "webapps.workerImageTag" -}}
{{- default (.Values.internal.serverRelease | lower) .Values.images.workerTag }}
{{- end }}

{{/*
Where license will be mounted into a server pod
*/}}
{{- define "webapps.serverLicenseMountPath" -}}
{{- printf "/home/mw-webapps-server/.matlab/%s_licenses/" (include "webapps.serverRelease" .) }}
{{- end }}

{{/*
server release running inside server pod
*/}}
{{- define "webapps.serverRelease" -}}
{{- default .Values.internal.serverRelease .Values.images.serverRelease }}
{{- end }}


{{/*
Section for runtimes to be placed into webapps.config, <Runtimes> tag

we do not want .numPrewarmedWorkers to be used here since server will not prewarm workers, k8s will
and it will cause change in prewarmed workers to restart the server and drop sessions 

*/}}
{{- define "webapps.runtimesXml" -}}
{{- range .Values.matlabRuntimes }}
{{- $runtimePath := "?" }}
{{- if ne $.Values.volumes.runtimes.mountType "embedded" }}
{{- $runtimePath = printf "/webapps/runtimes/%s" .release }}
{{- else }}
{{- $runtimePath = printf "/webapps/runtimes/embedded/%s" .release }}
{{- end }}
{{- printf "<Runtime Path=\"%s\" MaxPrewarmedWorkers=\"0\" />" $runtimePath }}
{{- end }}
{{- end }}

{{/*
Section for CSP to be placed into webapps.config, <ContentSecurityPolicy> tag
*/}}
{{- define "webapps.cspXml" -}}
{{- range $key, $value := . }}
        <{{ $key }}>{{ $value }}</{{ $key }}>
{{- end }}
{{- end }}

{{/*
Name of the worker set (per runtime)
Format: webapps-worker-$WEBAPPS_WORKER_RUNTIME_LABEL
where WEBAPPS_WORKER_RUNTIME_LABEL is taken from releasenum.ver of the respective runtime
*/}}
{{- define "webapps.workerSetName" -}}
{{- printf "webapps-worker-%s" . | lower }}
{{- end }}

{{/*
WEBAPPS_WORKER_RUNTIME_VER - is taken from mcrversion.ver of the respective runtime
.item - full path to matlab runtime
.global - .
*/}}
{{- define "webapps.workerRuntimeVer" -}}
{{- cat .item "/toolbox/compiler/mcrversion.ver" }}
{{- end }}

{{/*
*/}}
{{- define "webapps.serverServiceAddress" -}}
{{- printf "https://%s.%s.svc.cluster.local:%0.f" .Values.internal.webappsServiceName .Release.Namespace .Values.internal.webappsServicePort }}
{{- end }}

{{/* 
  Max file size configuration value with units. Default is 100m
*/}}
{{- define "webapps.maxAppUploadSizeStr" -}}
{{- $v := .Values.webAppServerSettings.maxAppUploadSizeMB -}}
{{- if and ($v) (ne (toString $v) "") -}}
{{- printf "%sm" (toString $v) -}}
{{ else }}
{{- printf "100m" -}}
{{- end -}}
{{- end -}}

{{/*
  Add to NetworkPolicy egress user additions
  params: 
        .policy - user settings
        .defaultPolicy - system settings

  Based on https://github.mathworks.com/development/mos-worker/blob/main/deployment/chart/matlab-pool-v2/templates/matlab-networkpolicy.yaml
*/}}
{{- define "webapps.appendToEgress" -}}
  {{ $additionalAllowedPorts := .policy.additionalAllowedPorts -}}
  {{ $additionalEgress := .policy.additionalEgress -}}
  {{ if .policy.egress }}
# got egress from user settings
    {{ toYaml .policy.egress | nindent 4 }}
  {{ else if or $additionalAllowedPorts $additionalEgress }}
# Merge to the first block and append other elements of the array
    {{ $defaultEgress := get .defaultPolicy "egress" -}}
    {{ if (and $additionalAllowedPorts $defaultEgress) }}
# Got $additionalAllowedPorts
      {{ if gt (len $defaultEgress) 0 }}
# Got $defaultEgress
        {{ $defaultEgressElement := index $defaultEgress 0 }}
        {{ $defaultPorts := get $defaultEgressElement "ports" -}}
        {{ $targetPorts := concat $defaultPorts $additionalAllowedPorts | uniq -}}
        {{ "- ports:" | nindent 4 }}
        {{ toYaml $targetPorts | nindent 6 }}
        {{ "to:" | nindent 6 }}
        {{ $defaultipBlock := get $defaultEgressElement "to" -}}
        {{ if $defaultipBlock }}
          # got $defaultipBlock
          {{ toYaml $defaultipBlock | nindent 6 }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{ with $additionalEgress }}
      {{ if not $additionalAllowedPorts }}
# Do not have $additionalAllowedPorts
        {{ if $defaultEgress }}
          # have $defaultEgress
          {{ toYaml $defaultEgress | nindent 4 }}
        {{- end }}  
      {{- end }}
      # printing $additionalEgress
      {{ toYaml . | nindent 4 }}
    {{- end }}
  {{ else }}
    {{ if .defaultPolicy.egress }}
      # printing .defaultPolicy.egress
      {{ toYaml .defaultPolicy.egress | nindent 4 }}
    {{- end }}
  {{- end }}

{{- end }}
