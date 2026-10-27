#!/usr/bin/env bash
# 온프렘 Argo CD 설치 + 앱(newsbrief) 넘겨받기 (1회, k8s-cp에서 관리자 kubeconfig로 실행)
# 1) Argo CD 설치 2) deploy/onprem 태그 브랜치 확인 3) Application 적용 4) 동기화·재시작 여부 확인 5) Helm 릴리스 기록 정리
# 차트 렌더링 결과는 Helm 배포 때와 같아서 파드는 재시작되지 않는다. 마지막에 확인한다
set -euo pipefail
cd "$(dirname "$0")/.."
NS=news
REPO=https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-infra.git

echo "== 1. Argo CD 설치 (argocd 네임스페이스)"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
VERSION="${ARGOCD_CHART_VERSION:-$(helm search repo argo/argo-cd -o json | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -1)}"
echo "차트 버전: argo/argo-cd $VERSION (argocd/README.md에 기록)"
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version "$VERSION" -f argocd/values.yaml --wait --timeout 10m
kubectl apply -f k8s/onprem/argocd-rbac.yaml
kubectl -n argocd get pods

echo "== 2. 태그 브랜치(deploy/onprem) 확인"
if ! git ls-remote --exit-code "$REPO" refs/heads/deploy/onprem >/dev/null; then
  B="$(kubectl get deployment/api -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')"
  F="$(kubectl get deployment/frontend -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')"
  echo "deploy/onprem 브랜치가 아직 없습니다. 맥에서 아래를 실행한 뒤 이 스크립트를 다시 실행하세요 (Argo CD 설치는 이미 끝나 다시 해도 그대로)"
  echo "  bash create_deploy_onprem_branch.sh $B $F"
  exit 0
fi

echo "== 3. 파드 시작 시각 기록"
kubectl get pods -n "$NS" -l 'app in (api,worker,frontend,redis,mysql)' \
  -o custom-columns=NAME:.metadata.name,START:.status.startTime --no-headers | sort > /tmp/argocd-before.txt
cat /tmp/argocd-before.txt

echo "== 4. Application 적용 (newsbrief-onprem)"
kubectl apply -f argocd/newsbrief-onprem.yaml
for i in $(seq 1 30); do
  st="$(kubectl -n argocd get application newsbrief-onprem -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)"
  echo "  $st"
  [ "$st" = "Synced/Healthy" ] && break
  [ "$i" = 30 ] && { echo "5분 안에 Synced/Healthy가 되지 않음. Argo CD 화면에서 확인하세요"; exit 1; }
  sleep 10
done

echo "== 5. 재시작 여부 (3번과 같아야 함)"
kubectl get pods -n "$NS" -l 'app in (api,worker,frontend,redis,mysql)' \
  -o custom-columns=NAME:.metadata.name,START:.status.startTime --no-headers | sort > /tmp/argocd-after.txt
if diff -q /tmp/argocd-before.txt /tmp/argocd-after.txt >/dev/null; then
  echo "파드 변화 없음"
else
  echo "파드가 바뀌었습니다. 아래 차이를 확인하세요"; diff /tmp/argocd-before.txt /tmp/argocd-after.txt || true
fi

echo "== 6. Helm 릴리스 기록 정리 (리소스는 그대로, 이제 Argo CD가 관리)"
kubectl -n "$NS" delete configmap -l owner=helm,name=newsbrief --ignore-not-found
echo "완료. Argo CD 화면: http://<k8s-cp Tailscale IP>:30880 (admin 비밀번호는 argocd/README.md)"
