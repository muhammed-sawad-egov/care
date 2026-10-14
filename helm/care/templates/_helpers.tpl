{{- define "care.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "care.fullname" -}}
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

{{- define "care.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "care.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Usage: include "care.selectorLabels" (dict "ctx" $ "component" "api") */}}
{{- define "care.selectorLabels" -}}
app.kubernetes.io/name: {{ include "care.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "care.backendImage" -}}
{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}
{{- end }}

{{- define "care.backendSecretName" -}}
{{- default (printf "%s-backend" (include "care.fullname" .)) .Values.backend.existingSecret }}
{{- end }}

{{/* Pod annotations for backend pods: roll them when the chart-managed Secret changes. */}}
{{- define "care.backendPodAnnotations" -}}
{{- if not .Values.backend.existingSecret }}
annotations:
  checksum/secret: {{ toJson .Values.backend.secretEnv | sha256sum }}
{{- end }}
{{- end }}

{{/* Env shared by every backend container (api, worker, beat, migrations). */}}
{{- define "care.backendEnv" -}}
env:
  {{- range $k, $v := .Values.backend.env }}
  - name: {{ $k }}
    value: {{ $v | quote }}
  {{- end }}
  {{- /* In-chart services override any host/URL in the Secret (env wins over envFrom). */}}
  {{- if .Values.postgresql.enabled }}
  - name: POSTGRES_HOST
    value: {{ include "care.fullname" . }}-postgres
  - name: POSTGRES_PORT
    value: "5432"
  # $(VAR) expands POSTGRES_USER/PASSWORD/DB from the Secret below.
  - name: DATABASE_URL
    value: postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@{{ include "care.fullname" . }}-postgres:5432/$(POSTGRES_DB)
  {{- end }}
  {{- if .Values.redis.enabled }}
  - name: REDIS_URL
    value: redis://{{ include "care.fullname" . }}-redis:6379/0
  - name: CELERY_BROKER_URL
    value: redis://{{ include "care.fullname" . }}-redis:6379/0
  {{- end }}
  {{- if .Values.minio.enabled }}
  - name: BUCKET_ENDPOINT
    value: http://{{ include "care.fullname" . }}-minio:9000
  - name: BUCKET_EXTERNAL_ENDPOINT
    {{- if .Values.minio.externalEndpoint }}
    value: {{ .Values.minio.externalEndpoint | quote }}
    {{- else }}
    value: {{ printf "http://%s" (required "minio.host or minio.externalEndpoint is required when minio.enabled" .Values.minio.host) | quote }}
    {{- end }}
  {{- end }}
envFrom:
  - secretRef:
      name: {{ include "care.backendSecretName" . }}
{{- end }}

{{- define "care.backendPodCommon" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.backend.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.backend.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.backend.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* Usage: include "care.pluginName" (dict "ctx" $ "name" .name) */}}
{{- define "care.pluginName" -}}
{{- printf "%s-fe-%s" (include "care.fullname" .ctx) .name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Static hostPath PV for an in-chart service (postgres/redis/minio), pre-bound to its PVC so the
data lives in a fixed node directory (on k3d: a host folder mounted into every node, shared
with docker compose). Retain + resource-policy keep: Helm/k8s never delete the files.
Usage: include "care.hostPathPV" (dict "ctx" $ "component" "postgres" "claim" "data-care-postgres-0" "persistence" $pg.persistence)
*/}}
{{- define "care.hostPathPV" -}}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: {{ include "care.fullname" .ctx }}-{{ .component }}-data
  labels:
    {{- include "care.labels" .ctx | nindent 4 }}
    app.kubernetes.io/component: {{ .component }}
  annotations:
    helm.sh/resource-policy: keep
spec:
  capacity:
    storage: {{ .persistence.size }}
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  claimRef:
    namespace: {{ .ctx.Release.Namespace }}
    name: {{ .claim }}
  hostPath:
    path: {{ .persistence.hostPath }}
    type: DirectoryOrCreate
{{- end }}

{{/* PVC spec fields: bind to the hostPath PV when set, else dynamic provisioning. */}}
{{- define "care.pvcStorage" -}}
accessModes: ["ReadWriteOnce"]
{{- if .persistence.hostPath }}
storageClassName: ""
volumeName: {{ include "care.fullname" .ctx }}-{{ .component }}-data
{{- else if .persistence.storageClass }}
storageClassName: {{ .persistence.storageClass }}
{{- end }}
resources:
  requests:
    storage: {{ .persistence.size }}
{{- end }}
