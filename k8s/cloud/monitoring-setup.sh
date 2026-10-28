#!/usr/bin/env bash
# EKS 모니터링(kube-prometheus-stack)을 올린다 (M5-8). 맥에서 실행, 다시 실행해도 같은 결과
#   cd <infra 저장소> && bash k8s/cloud/monitoring-setup.sh
# 필요: MFA 세션(AWS_PROFILE), kubectl context team01-eks, helm
# 대시보드·알림 규칙·백엔드 PodMonitor는 온프렘과 같은 파일(k8s/onprem/monitoring/)을 쓴다
set -euo pipefail
cd "$(dirname "$0")/../.."
CTX="${CTX:-team01-eks}"
KPS_VERSION=92.10.1
TRAEFIK_VERSION=41.7.1
K() { kubectl --context "$CTX" "$@"; }

echo "== 0. 노드별 파드 칸 (t3.medium 최대 17개)"
command -v helm >/dev/null || { echo "helm이 없습니다 (macOS: brew install helm)"; exit 1; }
K get pods -A --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
  | sort | uniq -c | awk '{print "  "$2": "$1"/17"}'

echo "== 1. Grafana 관리자 Secret (값은 저장소·화면에 두지 않는다)"
K create namespace monitoring --dry-run=client -o yaml | K apply -f - >/dev/null
if K -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  echo "  이미 있음 (grafana-admin)"
else
  read -rsp "  Grafana admin 비밀번호 입력(화면에 안 보임): " GRAFANA_PW; echo
  [ -n "$GRAFANA_PW" ] || { echo "  비밀번호가 비었습니다"; exit 1; }
  K -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$GRAFANA_PW" >/dev/null
  unset GRAFANA_PW
  echo "  만듦"
fi

echo "== 2. kube-prometheus-stack $KPS_VERSION"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm --kube-context "$CTX" upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version "$KPS_VERSION" -n monitoring -f k8s/cloud/monitoring-values.yaml --wait --timeout 10m

echo "== 3. 대시보드·알림 규칙·백엔드 PodMonitor (온프렘과 같은 파일)"
K apply -f k8s/onprem/monitoring/

echo "== 4. Traefik 지표 ServiceMonitor 켜기 (eks-setup.sh는 CRD가 없을 때 꺼서 설치함)"
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update traefik >/dev/null
helm --kube-context "$CTX" upgrade --install traefik traefik/traefik --version "$TRAEFIK_VERSION" \
  -n traefik -f onprem/traefik-values.yaml --wait --timeout 5m

echo "== 5. 상태"
K -n monitoring get pods -o wide --no-headers | awk '{print "  "$1, $3, $7}'
echo "  수집 대상이 올라오기까지 1~2분 걸린다. 확인:"
echo "    kubectl --context $CTX -n monitoring port-forward svc/kps-prometheus 9090:9090  → http://localhost:9090/targets"
echo "    kubectl --context $CTX -n monitoring port-forward svc/kps-grafana 3000:80       → http://localhost:3000 (대시보드 'NewsBrief 서비스')"
