# newsbrief Helm 차트 (M5-6)

온프렘·AWS 앱 배포에 쓰는 Helm 차트. 원래 `k8s/base` + `k8s/onprem` + `k8s/cloud` 매니페스트였고, M5-6에서 차트로 옮겼다 (M5-7 전환 후 옛 매니페스트는 삭제).
렌더링 결과는 기존 매니페스트와 같고, Helm 관리 라벨만 추가된다 (selector·파드 라벨은 그대로라 전환만으로 재시작되지 않음).

온프렘(deploy-onprem)과 AWS(deploy-aws) 배포 모두 M5-7부터 이 차트로 한다.

## 구조

| 파일 | 내용 |
|---|---|
| `values.yaml` | 공통 기본값 (이미지 저장소, 리소스, 복제 수, 공통 설정) |
| `values-onprem.yaml` | 온프렘: 클러스터 안 MySQL·Redis, 프론트 포함, 쿠키 Secure 끔, AI mock |
| `values-aws.yaml` | AWS: RDS·ElastiCache(ExternalName), 프론트 없음(S3·CloudFront), Traefik Ingress |
| `templates/` | api, worker, batch, frontend, mysql, redis, backend-config, ingress |

환경 차이는 values 파일에만 있다. 템플릿은 두 환경이 같다.

## 사전 준비 (차트가 만들지 않음)

- Secret `mysql-secret` (password, root-password), `app-secret` (JWT_SECRET)
- GHCR pull Secret (`ghcr-pull`, default ServiceAccount에 연결)

비밀값은 저장소와 values 파일에 두지 않는다.

## 렌더링

```bash
# 온프렘
helm template newsbrief charts/newsbrief -n news -f charts/newsbrief/values-onprem.yaml \
  --set-string backend.image.tag=<백엔드 SHA 40자리> --set-string frontend.image.tag=<프론트 SHA 40자리>

# AWS (주소는 GitHub Variables 값. 저장소에 쓰지 않는다)
helm template newsbrief charts/newsbrief -n news -f charts/newsbrief/values-aws.yaml \
  --set-string backend.image.tag=<백엔드 SHA> \
  --set mysql.externalHost=<RDS 주소> --set redis.externalHost=<Redis 주소> \
  --set-string backend.config.CORS_ALLOWED_ORIGINS=<https://app.도메인> \
  --set-string backend.config.AI_MODE=<mock|bedrock>
```

안전장치: 이미지 태그가 비었거나 커밋 SHA 40자리가 아니면(`latest` 등), 또는 `backend.config` 값이 비었으면 렌더링이 실패한다.

## 클러스터와 비교 (읽기 전용, 적용하지 않음)

```bash
B=$(kubectl -n news get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
F=$(kubectl -n news get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
helm template newsbrief charts/newsbrief -n news -f charts/newsbrief/values-onprem.yaml \
  --set-string backend.image.tag=$B --set-string frontend.image.tag=$F | kubectl diff -n news -f -
```

차이가 Helm 라벨(`app.kubernetes.io/*`, `helm.sh/chart`) 추가뿐이면 정상이다.

## 온프렘 Helm 배포 (M5-7)

- workflow: `.github/workflows/deploy-onprem.yml`이 `helm upgrade --install newsbrief charts/newsbrief -f values-onprem.yaml`로 배포한다
- 한 앱만 배포할 때 다른 앱의 태그는 클러스터에서 지금 값을 읽어 그대로 넘긴다
- 릴리스 기록은 ConfigMap에 저장한다 (`HELM_DRIVER=configmap`). 배포 SA에 Secret 권한을 주지 않기 위해서다. 관리자가 helm 명령을 쓸 때도 같은 값을 줘야 같은 릴리스로 보인다
- 백엔드·프론트 배포가 같은 릴리스를 쓰므로 workflow 동시 실행을 한 줄로 세웠다 (concurrency `deploy-onprem`)
- 처음 한 번은 기존 리소스를 Helm으로 넘겨야 한다: `bash onprem/helm-adopt.sh` (cp, 관리자 kubeconfig)

관리자 확인 명령

```bash
export HELM_DRIVER=configmap
helm list -n news
helm history newsbrief -n news
helm get values newsbrief -n news
```

롤백은 지금처럼 deploy-onprem 수동 실행(app, 이전 SHA)으로 한다. `helm rollback`은 다른 앱 태그까지 같이 되돌리므로 쓰지 않는다.

## AWS Helm 배포 (M5-7)

- workflow: `.github/workflows/deploy-aws.yml`이 `values-aws.yaml`로 배포한다
- DB·Redis 주소, 화면 주소, AI 모드는 GitHub Variables(`AWS_DB_HOST`, `AWS_REDIS_HOST`, `AWS_APP_ORIGIN`, `AWS_AI_MODE`)를 `--set-string`으로 넘긴다. 저장소에는 주소가 없다
- 이미지가 같고 설정 값만 바뀌면(AI 모드 전환 등) api·worker를 재시작한다. ConfigMap의 data만 비교한다
- 처음 한 번: AWS cp(root)에서 `bash k8s/cloud/helm-adopt.sh` (지금 클러스터의 주소·설정 값을 읽어 같은 값으로 넘김)

## 남은 일

1. GitOps(Argo CD): 이미지 태그를 values 파일에 기록하고 Argo CD가 동기화
