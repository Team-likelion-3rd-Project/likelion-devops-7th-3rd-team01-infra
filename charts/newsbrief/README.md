# newsbrief Helm 차트 (M5-6)

`k8s/base` + `k8s/onprem` + `k8s/cloud` 매니페스트를 차트 하나로 옮긴 것이다.
렌더링 결과는 기존 매니페스트와 같고, Helm 관리 라벨만 추가된다 (selector·파드 라벨은 그대로라 전환만으로 재시작되지 않음).

이 PR은 차트만 추가한다. 배포 workflow는 아직 `k8s/` 매니페스트를 쓰고, Helm 배포 전환은 M5-7에서 한다.

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

## M5-7에서 할 일 (Helm 배포 전환)

1. 기존 리소스에 Helm 소유 표시 추가 (`meta.helm.sh/release-name`, `meta.helm.sh/release-namespace` 주석, `app.kubernetes.io/managed-by=Helm` 라벨). 없으면 `helm install`이 "이미 있는 리소스"로 실패한다
2. 배포 전용 ServiceAccount 권한: Helm은 릴리스 기록을 Secret에 저장한다. Secret 권한을 주지 않으려면 `HELM_DRIVER=configmap`을 쓴다. 온프렘은 StatefulSet(mysql) 권한도 필요하다
3. 앱 하나만 배포할 때 다른 앱의 이미지 태그를 유지하는 방법 (클러스터의 현재 태그를 읽어 넘기거나, GitOps 단계에서 values에 태그를 기록)
4. deploy-onprem·deploy-aws를 `helm upgrade --install`로 교체
