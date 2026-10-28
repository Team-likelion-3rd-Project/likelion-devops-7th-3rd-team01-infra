# AWS 앱 배포 (EKS + Argo CD)

M5-3부터 AWS 운영 클러스터는 EKS(`team01-eks`)이고, 배포는 온프렘과 같은 GitOps 방식이다.

```
백엔드 main 머지 → 백엔드 CI가 이미지 push → deploy-aws 호출 (GitHub 호스팅 러너, 클러스터 접근 없음)
→ deploy/aws 브랜치에 develop을 합치고 태그 커밋 (deploy/tags-aws.yaml)
→ EKS 안의 Argo CD(newsbrief-aws)가 3분 안에 반영
→ workflow가 공개 API로 확인 (X-App-Version 헤더가 있으면 SHA 비교, 없으면 200 확인)
```

| 무엇 | 어디 |
|---|---|
| 앱 차트, values-aws.yaml | develop `charts/newsbrief` (PR) |
| 이미지 태그 | deploy/aws `deploy/tags-aws.yaml` (deploy-aws workflow만 커밋) |
| RDS·Redis 주소, 화면 주소, AI 모드 | EKS의 Argo CD Application `newsbrief-aws` (저장소에 없음, 예시: `argocd/newsbrief-aws.yaml.example`) |
| Secret (DB 비밀번호, JWT, GHCR) | EKS news 네임스페이스 (저장소에 없음) |

- AWS는 운영이라 develop을 deploy/aws에 **자동으로 합치지 않는다.** deploy-aws가 돌 때만 차트 변경이 함께 나간다 (온프렘은 sync-deploy-onprem이 자동으로 합침)
- 롤백: deploy-aws를 이전 SHA로 수동 실행 (또는 deploy/aws의 태그 커밋 되돌리기)

## GitHub Variables

| 이름 | 쓰임 |
|---|---|
| `AWS_APP_ORIGIN` | `https://app.<도메인>`. deploy-aws가 배포 후 확인에 사용 |

`AWS_DB_HOST`, `AWS_REDIS_HOST`, `AWS_AI_MODE`는 kubeadm 시절 값이다. 이제는 Argo CD Application에 있으므로 쓰지 않는다.

## AI 모드 바꾸기 (mock ↔ bedrock)

```bash
kubectl --context team01-eks -n argocd patch application newsbrief-aws --type json \
  -p '[{"op":"replace","path":"/spec/source/helm/parameters/3/value","value":"mock"}]'
# 설정(ConfigMap)만 바뀌므로 파드를 다시 띄워야 반영된다
kubectl --context team01-eks -n news rollout restart deploy/api deploy/worker
```

## EKS를 새로 만들었을 때 (클러스터 재생성·M5-5)

1. `terraform apply` (terraform/aws-eks.md)
2. `aws eks update-kubeconfig --name team01-eks --alias team01-eks`
3. `bash k8s/cloud/eks-setup.sh` : Traefik, Secret, Argo CD, Application, Pod Identity·30080 경로 확인
   - Secret은 기존 kubeadm 클러스터가 있으면 `KUBEADM_CP_ID=<인스턴스 ID>`로 복사, 없으면 `read -s`로 입력
4. ALB 전환: `terraform.tfvars`에 `alb_backend = "eks"` → apply

## 태그 브랜치 만들기 (deploy/aws가 없을 때)

```bash
git checkout develop && git pull && git checkout -b deploy/aws
mkdir -p deploy
cat > deploy/tags-aws.yaml <<'TAGS'
# deploy-aws workflow가 갱신한다. Argo CD(EKS)가 이 파일의 태그로 AWS에 배포한다
backend:
  image:
    tag: "<지금 운영 중인 백엔드 SHA 40자리>"
TAGS
git add deploy/tags-aws.yaml && git commit -m "deploy(aws): 초기 태그" && git push -u origin deploy/aws
git checkout develop
```

## Argo CD 화면 (EKS)

```bash
kubectl --context team01-eks -n argocd port-forward svc/argocd-server 8081:80
# 브라우저 http://localhost:8081 , 처음 비밀번호(cp가 아니라 맥에서만 확인, 채팅에 올리지 않음):
kubectl --context team01-eks -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

로그인 후 비밀번호를 바꾸고 `argocd-initial-admin-secret`을 지운다.

## 이전 방식 (kubeadm, M4-5 ~ M5-7)

kubeadm control plane의 self-hosted runner(라벨 `aws`)가 Helm으로 배포했다. EKS 전환 후 kubeadm EC2는 되돌리기용으로 중지해 두었고, 정리할 때 runner 등록도 지운다 (infra 저장소 Settings → Actions → Runners → aws-cp).
