#!/usr/bin/env bash
# AWS: 기존 kubectl 리소스를 Helm 릴리스(newsbrief)로 넘기는 1회 작업 (M5-7)
# AWS cp에서 root로 실행 (SSM 접속 → sudo -i): bash k8s/cloud/helm-adopt.sh
# 접속 주소·화면 주소·AI 모드는 지금 클러스터에 적용된 값을 읽어 그대로 쓴다 (저장소에 주소를 두지 않음)
# 차트 결과가 클러스터와 같으면(라벨만 추가) 파드는 재시작되지 않는다. 마지막에 재시작 여부를 확인한다
set -euo pipefail
cd "$(dirname "$0")/../.."
NS=news
RELEASE=newsbrief
CHART=charts/newsbrief
export HELM_DRIVER=configmap   # 배포 workflow와 같은 저장 방식이어야 같은 릴리스로 본다

RESOURCES="deployment/api deployment/worker cronjob/batch configmap/backend-config
service/api service/mysql service/redis ingress/news-api"

SHA="$(kubectl get deployment/api -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')"
DB_HOST="$(kubectl get service/mysql -n "$NS" -o jsonpath='{.spec.externalName}')"
REDIS_HOST="$(kubectl get service/redis -n "$NS" -o jsonpath='{.spec.externalName}')"
APP_ORIGIN="$(kubectl get configmap/backend-config -n "$NS" -o jsonpath='{.data.CORS_ALLOWED_ORIGINS}')"
AI_MODE="$(kubectl get configmap/backend-config -n "$NS" -o jsonpath='{.data.AI_MODE}')"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "현재 이미지 태그를 읽지 못함: '$SHA'"; exit 1; }
for v in DB_HOST REDIS_HOST APP_ORIGIN AI_MODE; do [ -n "${!v}" ] || { echo "$v 값을 클러스터에서 읽지 못함"; exit 1; }; done
args=(-n "$NS" -f "$CHART/values-aws.yaml"
  --set-string backend.image.tag="$SHA"
  --set-string mysql.externalHost="$DB_HOST"
  --set-string redis.externalHost="$REDIS_HOST"
  --set-string backend.config.CORS_ALLOWED_ORIGINS="$APP_ORIGIN"
  --set-string backend.config.AI_MODE="$AI_MODE")

if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  echo "이미 Helm 릴리스가 있습니다. 넘길 필요가 없습니다."; helm list -n "$NS"; exit 0
fi

echo "== 1. 바뀔 줄 (Helm 라벨 3종 외에는 없어야 함)"
helm template "$RELEASE" "$CHART" "${args[@]}" | kubectl diff -n "$NS" -f - | grep -E '^[-+] ' | sort | uniq -c || true
read -r -p "라벨만 바뀌면 yes 입력: " ok
[ "$ok" = yes ] || { echo "중단"; exit 1; }

echo "== 2. 파드 시작 시각 기록"
kubectl get pods -n "$NS" -l 'app in (api,worker)' \
  -o custom-columns=NAME:.metadata.name,START:.status.startTime --no-headers | sort > /tmp/helm-adopt-before.txt
cat /tmp/helm-adopt-before.txt

echo "== 3. Helm 소유 표시"
for r in $RESOURCES; do
  kubectl -n "$NS" annotate "$r" meta.helm.sh/release-name="$RELEASE" meta.helm.sh/release-namespace="$NS" --overwrite >/dev/null
  kubectl -n "$NS" label "$r" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null
  echo "  $r"
done

echo "== 4. 첫 Helm 배포 (지금과 같은 태그·설정)"
helm upgrade --install "$RELEASE" "$CHART" "${args[@]}" --history-max 10
helm list -n "$NS"

echo "== 5. 재시작 여부 (위 2번과 같아야 함)"
sleep 5
kubectl get pods -n "$NS" -l 'app in (api,worker)' \
  -o custom-columns=NAME:.metadata.name,START:.status.startTime --no-headers | sort > /tmp/helm-adopt-after.txt
if diff -q /tmp/helm-adopt-before.txt /tmp/helm-adopt-after.txt >/dev/null; then
  echo "파드 변화 없음. 전환 완료"
else
  echo "파드가 바뀌었습니다. 아래 차이를 확인하세요"; diff /tmp/helm-adopt-before.txt /tmp/helm-adopt-after.txt || true
fi
