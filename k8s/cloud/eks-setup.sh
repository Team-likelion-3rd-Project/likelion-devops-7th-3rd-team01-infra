#!/usr/bin/env bash
# EKS에 Traefik·Secret·Argo CD·앱(newsbrief-aws)을 올린다 (M5-3). 맥에서 실행, ALB 전환은 하지 않는다
# 클러스터를 새로 만들었을 때(terraform apply 후) 한 번 실행한다. 다시 실행해도 같은 결과
#   cd <infra 저장소> && bash k8s/cloud/eks-setup.sh
# 필요: MFA 세션(AWS_PROFILE), kubectl context team01-eks (aws eks update-kubeconfig --name team01-eks --alias team01-eks), helm
# Secret 값은 화면에 출력하지 않는다
#   KUBEADM_CP_ID를 주면 기존 kubeadm 클러스터에서 SSM으로 복사하고, 없으면 read -s로 직접 입력받는다
set -euo pipefail
cd "$(dirname "$0")/../.."
CTX="${CTX:-team01-eks}"
NS=news
TRAEFIK_VERSION=41.7.1
ARGOCD_VERSION=10.11.6
REPO=https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-infra.git
export AWS_PAGER=""
K() { kubectl --context "$CTX" "$@"; }

echo "== 0. 사전 확인"
command -v helm >/dev/null || { echo "helm이 없습니다 (macOS: brew install helm)"; exit 1; }
K get nodes --no-headers | awk '{print "  "$1, $2}'
DB_HOST="$(terraform -chdir=terraform output -raw db_endpoint)"
REDIS_HOST="$(terraform -chdir=terraform output -raw redis_endpoint)"
DOMAIN="$(sed -n 's/^domain_name *= *"\(.*\)"/\1/p' terraform/terraform.tfvars)"
APP_ORIGIN="https://app.${DOMAIN}"
AI_MODE="${AI_MODE:-bedrock}"
[ -n "$DB_HOST" ] && [ -n "$REDIS_HOST" ] && [ -n "$DOMAIN" ] || { echo "terraform output 또는 domain_name을 읽지 못함"; exit 1; }
echo "  설정 값 확인 (주소는 출력하지 않음), AI_MODE=$AI_MODE"

echo "== 1. Traefik (NodePort 30080, ALB 대상 그룹 team01-eks-web)"
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update traefik >/dev/null
helm --kube-context "$CTX" upgrade --install traefik traefik/traefik --version "$TRAEFIK_VERSION" \
  -n traefik --create-namespace -f onprem/traefik-values.yaml \
  --set metrics.prometheus.serviceMonitor.enabled=false --wait --timeout 5m

echo "== 2. news 네임스페이스와 Secret"
K create namespace "$NS" --dry-run=client -o yaml | K apply -f -
if K -n "$NS" get secret mysql-secret app-secret ghcr-pull >/dev/null 2>&1; then
  echo "  이미 있음 (mysql-secret, app-secret, ghcr-pull)"
elif [ -n "${KUBEADM_CP_ID:-}" ]; then
  # 기존 kubeadm 클러스터에서 SSM으로 복사 (값은 화면에 나오지 않음)
  params="$(mktemp)"; tmp="$(mktemp)"; chmod 600 "$tmp"
  python3 -c 'import json; print(json.dumps({"commands":["kubectl --kubeconfig /etc/kubernetes/admin.conf -n news get secret mysql-secret app-secret ghcr-pull -o json"]}))' > "$params"
  id="$(aws ssm send-command --instance-ids "$KUBEADM_CP_ID" --document-name AWS-RunShellScript --parameters "file://$params" --query Command.CommandId --output text)"
  rm -f "$params"
  for _ in $(seq 1 30); do
    st="$(aws ssm get-command-invocation --command-id "$id" --instance-id "$KUBEADM_CP_ID" --query Status --output text 2>/dev/null || echo Pending)"
    [ "$st" = Success ] && break; sleep 2
  done
  aws ssm get-command-invocation --command-id "$id" --instance-id "$KUBEADM_CP_ID" --query StandardOutputContent --output text > "$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
p = sys.argv[1]
src = json.load(open(p))
items = [{"apiVersion": "v1", "kind": "Secret", "type": s["type"],
          "metadata": {"name": s["metadata"]["name"], "namespace": s["metadata"]["namespace"]},
          "data": s["data"]} for s in src["items"]]
json.dump({"apiVersion": "v1", "kind": "List", "items": items}, open(p, "w"))
PY
  K apply -f "$tmp"; rm -f "$tmp"
else
  # 직접 입력 (화면에 표시되지 않음). DB 비밀번호는 RDS의 news_app 계정 비밀번호
  read -r -s -p "news_app DB 비밀번호: " DBPW; echo
  read -r -s -p "JWT_SECRET (다른 환경과 같은 값이면 로그인 유지): " JWT; echo
  read -r -p "GHCR 사용자(GitHub 아이디): " GHUSER
  read -r -s -p "GHCR 토큰 (classic, read:packages): " GHPAT; echo
  K -n "$NS" create secret generic mysql-secret --from-literal=password="$DBPW" --dry-run=client -o yaml | K apply -f -
  K -n "$NS" create secret generic app-secret --from-literal=JWT_SECRET="$JWT" --dry-run=client -o yaml | K apply -f -
  K -n "$NS" create secret docker-registry ghcr-pull --docker-server=ghcr.io \
    --docker-username="$GHUSER" --docker-password="$GHPAT" --dry-run=client -o yaml | K apply -f -
  unset DBPW JWT GHPAT
fi
K -n "$NS" patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'

echo "== 3. 태그 브랜치 deploy/aws 확인"
git ls-remote --exit-code "$REPO" refs/heads/deploy/aws >/dev/null || {
  echo "  deploy/aws 브랜치가 없습니다. k8s/cloud/README.md의 '태그 브랜치 만들기'를 먼저 하세요"; exit 1; }

echo "== 4. Argo CD (화면은 port-forward로만)"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm --kube-context "$CTX" upgrade --install argocd argo/argo-cd --version "$ARGOCD_VERSION" \
  -n argocd --create-namespace -f argocd/values.yaml --set server.service.type=ClusterIP --wait --timeout 10m

echo "== 5. Application newsbrief-aws (주소·설정은 이 클러스터에만)"
app="$(mktemp)"; chmod 600 "$app"
sed -e "s|<RDS 주소: terraform output -raw db_endpoint>|$DB_HOST|" \
    -e "s|<Redis 주소: terraform output -raw redis_endpoint>|$REDIS_HOST|" \
    -e "s|https://app.<도메인>|$APP_ORIGIN|" \
    -e "s/<mock | bedrock>/$AI_MODE/" argocd/newsbrief-aws.yaml.example > "$app"
grep -q '<' "$app" && { echo "Application에 채우지 못한 값이 있습니다"; rm -f "$app"; exit 1; }
K apply -f "$app"; rm -f "$app"
for i in $(seq 1 40); do
  st="$(K -n argocd get application newsbrief-aws -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)"
  echo "  $st"; [ "$st" = "Synced/Healthy" ] && break
  [ "$i" = 40 ] && { K -n argocd get application newsbrief-aws -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'; exit 1; }
  sleep 15
done
K -n "$NS" get pods

echo "== 6. Bedrock Pod Identity (자격 증명 변수는 있고 액세스 키는 없어야 함)"
K -n "$NS" exec deploy/api -c api -- sh -c 'env | grep -o "^AWS_CONTAINER_[A-Z_]*" | sort -u; echo "access key 변수: $(env | grep -c "^AWS_ACCESS_KEY_ID=")"' || true

echo "== 7. 노드 30080 → Traefik → api 경로 (ALB 헬스체크와 같은 주소)"
for ip in $(K get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
  printf '  %s → ' "$ip"
  K run "hc-${ip//./-}" --rm -i --restart=Never --image=curlimages/curl:8.11.1 -q -- \
    curl -s -o /dev/null -w "%{http_code}\n" "http://$ip:30080/api/news/home"
done
echo "완료. 200이면 ALB 전환 준비 완료 (terraform.tfvars alb_backend = \"eks\")"
