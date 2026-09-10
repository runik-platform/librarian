{{/*Runik Platform
Copyright (C) 2023 namenmalkv@gmail.com
SPDX-License-Identifier: AGPL-3.0-only
*/}}

{{/*
Standard Kubernetes annotations
https://kubernetes.io/docs/reference/labels-annotations-taints/

Annotations store non-identifying metadata that is not used for selection.
They can contain structured or unstructured data and are ideal for:
- Build/release/deployment information
- Client tool configurations
- Human-readable descriptions
- External system references
*/}}
{{- define "common.annotations" -}}
{{- if .Values.description }}
kubernetes.io/description: {{ .Values.description | quote }}
{{- end }}
{{- with .Values.annotations }}
{{- toYaml . }}
{{- end }}
{{- end -}}