{{/*
공통 라벨. 리소스 자체의 metadata에만 붙인다.
selector와 파드 템플릿 라벨은 기존 매니페스트(app: <이름>)와 똑같이 둔다.
selector는 바꿀 수 없고, 파드 템플릿 라벨이 바뀌면 전환만으로 파드가 재시작되기 때문이다.
*/}}
{{- define "newsbrief.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: newsbrief
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/* 이미지 태그는 커밋 SHA 40자리만 허용 (latest·빈 값으로 배포되는 것 방지) */}}
{{- define "newsbrief.tag" -}}
{{- $tag := required (printf "%s.image.tag (커밋 SHA 40자리)가 필요합니다" .name) .tag -}}
{{- if not (regexMatch "^[0-9a-f]{40}$" $tag) -}}
{{- fail (printf "%s.image.tag는 커밋 SHA 40자리여야 합니다: %s" .name $tag) -}}
{{- end -}}
{{- $tag -}}
{{- end }}

{{- define "newsbrief.backendImage" -}}
{{ .Values.backend.image.repository }}:{{ include "newsbrief.tag" (dict "name" "backend" "tag" .Values.backend.image.tag) }}
{{- end }}

{{/* 재부팅 직후 MySQL·클러스터 DNS보다 앱이 먼저 떠서 재시작이 반복되던 문제 방지 */}}
{{- define "newsbrief.waitMysql" -}}
- name: wait-mysql
  image: {{ .Values.waitMysql.image }}
  command: ['sh', '-c', 'until nc -z -w 2 mysql 3306; do echo "MySQL 대기 중"; sleep 2; done']
  resources:
    requests: {cpu: 10m, memory: 16Mi}
    limits: {memory: 32Mi}
{{- end }}

{{/* 세 역할(api·worker·batch) 공통 환경 변수. 역할만 다르다 */}}
{{- define "newsbrief.backendEnv" -}}
- name: APP_ROLE
  value: {{ .role }}
- name: SPRING_DATASOURCE_PASSWORD
  valueFrom: {secretKeyRef: {name: mysql-secret, key: password}}
- name: JWT_SECRET
  valueFrom: {secretKeyRef: {name: app-secret, key: JWT_SECRET}}
{{- end }}
