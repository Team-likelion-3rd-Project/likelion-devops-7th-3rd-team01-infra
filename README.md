# AI 뉴스 브리핑 - infra

같은 앱을 온프레미스(develop)와 AWS EKS(main)에 배포하기 위한 인프라 저장소입니다. 두 환경 모두 **같은 Helm 차트를 Argo CD(GitOps)로** 배포하고, values 파일만 환경별로 다릅니다.

- 프로젝트 소개·위키·이슈·칸반: [likelion-devops-7th-3rd-team01](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01)
- 앱 저장소: [backend](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-backend) · [frontend](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-frontend)

## 배포 흐름

```
앱 머지 → 앱 CI가 이미지 push (GHCR, 커밋 SHA 태그) → 이 저장소의 배포 workflow 호출
→ workflow가 태그 브랜치에 develop을 합치고 이미지 태그 커밋
→ 클러스터 안의 Argo CD가 3분 안에 반영
→ workflow가 실행 중인 버전(SHA)을 확인
```

| | 온프레미스 (develop) | AWS (main) |
|---|---|---|
| workflow | `deploy-onprem` (클러스터 안 self-hosted runner, 반영 확인용) | `deploy-aws` (GitHub 호스팅 러너, 클러스터 접근 없음) |
| 태그 브랜치 | `deploy/onprem` (`deploy/tags-onprem.yaml`) | `deploy/aws` (`deploy/tags-aws.yaml`) |
| 차트 변경 반영 | develop 머지 시 `sync-deploy-onprem`이 자동으로 합침 | 운영이라 자동으로 합치지 않음. `deploy-aws`가 돌 때 함께 나감 |
| 확인 방법 | 롤아웃 완료 + 실행 버전 SHA | 공개 API 응답 헤더 `X-App-Version` SHA 비교 |
| 롤백 | 이전 SHA로 workflow 수동 실행 | 이전 SHA로 workflow 수동 실행 |

workflow는 클러스터를 직접 바꾸지 않습니다. 클러스터 상태는 Git에 적힌 대로 Argo CD가 맞춥니다.

## 환경 비교

| 항목 | 온프레미스 (develop) | AWS (main) |
|---|---|---|
| 클러스터 | VirtualBox VM 3대 kubeadm (control plane 1, worker 2) | EKS 1.35, 관리형 노드 t3.medium 2대 |
| 입구 | Traefik (NodePort) | ALB → Traefik |
| DB | MySQL StatefulSet (노드 로컬 디스크) | RDS MySQL db.t3.micro (Single-AZ) |
| Redis | 클러스터 내 Deployment | ElastiCache cache.t3.micro 1노드 |
| 화면 | Nginx 파드 | CloudFront + S3 |
| AI | mock (개발·테스트) | Bedrock Claude Haiku 5.5 (점검·시연 때만), 부하 테스트는 mock |
| 확장 | 고정 (api 2개) | HPA api 2~4개 (CPU 70%) |
| 모니터링 | kube-prometheus-stack | kube-prometheus-stack + CloudWatch(ALB·RDS·Redis) |
| 백업 | MySQL 덤프 매일 03:10, etcd 스냅샷 03:20, 7일 보관 | RDS 자동 백업 7일 |
| 환경 생성 | 설치 스크립트 (`onprem/`) | Terraform (`terraform/`) |

## 구조

| 경로 | 내용 |
|------|------|
| `charts/newsbrief/` | 앱 Helm 차트. 공통 템플릿 + `values-onprem.yaml`, `values-aws.yaml`. api HPA 포함 |
| `argocd/` | Argo CD 설치 값, Application(온프렘), AWS Application 예시 |
| `k8s/onprem/` | 온프렘 전용: 배포 SA 권한(rbac), 모니터링 대시보드·알림, 백업·복원 시험 |
| `k8s/cloud/` | EKS 배포 설명, 클러스터 준비·모니터링 설치 스크립트, AWS 지표 조회(`aws-metrics.sh`) |
| `onprem/` | VM·kubeadm 클러스터 설정, Traefik·모니터링 값, 백업 문서 |
| `terraform/` | AWS 환경 (network, data, eks, compute, frontend, identity 모듈) |
| `.github/workflows/` | 배포(`deploy-onprem`, `deploy-aws`, `sync-deploy-onprem`), PR 검사(`chart-check`, `terraform-check`) |

## 검증 결과

10/23~10/29에 두 환경에서 직접 측정했습니다. k6는 클러스터 밖 PC에서 실행했습니다. 상세 조건과 수치는 위키 [성능 테스트](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01/wiki/성능-테스트) · [장애 시나리오](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01/wiki/장애-시나리오)에 있습니다.

### 성능

| 시나리오 | 부하 | 온프렘 | EKS |
|---|---|---|---|
| 조회 | 200명 | p95 70ms, 실패 1.42% (VPN 경로 영향) | p95 29ms, 실패 0% |
| 질문 (mock AI) | 50명 | 접수 p95 46ms, FAILED 0 | 접수 p95 63ms, FAILED 0 |
| 스파이크 | 10초 만에 500명 | - | HPA 2→4→2, p95 36ms, 실패 0% |
| 롤링 배포 중 | 50명 | 실패 0건 | 실패 0건 |

부하 테스트로 찾은 병목 3건과 개선 결과:

| 병목 | 개선 | 결과 |
|---|---|---|
| 파드 시작 직후 느림 | readiness 전에 조회 API 예열 | p95 1.29초 → 332ms |
| DB 연결 과다 (RDS micro 한도) | 파드당 연결 풀 10 → 5 | RDS 연결 40 → 15 |
| 요약 배치 후 캐시가 비며 DB로 몰림 | 캐시를 지우지 않고 새 요약으로 덮어쓰기 | 스파이크 중 실패 3.32% → 0%, p95 1.09초 → 36ms |

### 장애 복구

| 장애 | 온프렘 | EKS |
|---|---|---|
| 노드 1대 다운 | 약 3분 10초 중단, 실패 39%. DB가 같은 노드 디스크에 있어 함께 중단, 사람이 VM 재시작 | 13초 중단, 실패 2.4%. 새 노드 자동 생성(70초), DB는 RDS라 영향 없음 |
| DB 중단 | MySQL 파드 삭제 → 27초 복구, 실패 8.6% | RDS 재부팅 52초, 실패 0.64% |
| Redis 중단 | 파드 삭제 6초, 실패 0 | ElastiCache 재부팅 89초, 실패 0 (조회는 DB에서 응답) |
| 데이터 복원 | mysqldump를 임시 DB에 복원, 건수 일치 | RDS 자동 백업 7일 |

앱 계층(파드 재생성, 롤링 배포, Redis 장애)은 두 환경 모두 같은 수준으로 견딥니다. 차이는 인프라 계층에서 납니다. EKS는 노드 자동 교체와 관리형 DB로 사람 없이 복구되고, 온프렘은 노드·DB·백업이 같은 물리 자원에 묶여 있어 사람이 개입해야 합니다.

### 비용 (AWS, 10/29 기준)

실제 구성 × 서울 온디맨드 단가로 계산했습니다 (세금 제외).

| 항목 | 구성 | 켜 두는 시간 |
|---|---|---|
| EKS 컨트롤 플레인 | 1개 | 24시간 |
| RDS · ElastiCache | micro, 단일 노드 | 24시간 |
| ALB | 1개 | 24시간 |
| EKS 노드 | t3.medium 2대 | 낮 약 10시간 (밤 0대) |
| NAT | 1개 | 낮 약 10시간 (밤 삭제) |
| **합계** | | **하루 약 $6.3, 30일 약 $190** |

설계 견적(월 약 $551, Multi-AZ·NAT 2개·t3.large)보다 약 65% 낮습니다. 대신 RDS·Redis 장애 전환은 없습니다. Terraform 변수 `db_multi_az`, `redis_replicas`로 켤 수 있습니다.

## 알려진 한계

- Traefik이 1개라 그 노드가 죽으면 잠깐 끊깁니다 (EKS 노드 다운 13초 중단의 원인). 복제본 2개로 줄일 수 있습니다.
- EKS 노드가 2대라 1대가 죽으면 새 노드가 뜰 때까지 api가 1개로 줄어듭니다.
- 온프렘 MySQL과 백업이 VM 로컬 디스크에 있어, VM 디스크가 망가지면 백업도 함께 잃습니다. 외부(S3) 복사가 필요합니다.
- 온프렘 control plane이 1대라 단일 장애 지점입니다. etcd 복원 시험은 위험도 때문에 하지 않았습니다.
- 워커 자동 확장(KEDA)은 검토만 하고 적용하지 않았습니다.

## 운영 문서

| 작업 | 문서 |
|---|---|
| Argo CD 설치·롤백·장애 시험 때 selfHeal 끄기 | [argocd/README.md](argocd/README.md) |
| EKS 배포·AI 모드 전환·HPA·모니터링 | [k8s/cloud/README.md](k8s/cloud/README.md) |
| Helm 차트 렌더링·values | [charts/newsbrief/README.md](charts/newsbrief/README.md) |
| Terraform 적용 규칙·비용 주의 | [terraform/README.md](terraform/README.md) |
| AWS 환경 재생성 절차 | [terraform/rebuild.md](terraform/rebuild.md) |
| 온프렘 백업·복원 | [onprem/backup.md](onprem/backup.md) |

## 비밀 값

비밀번호·API 키·kubeconfig는 이 저장소에 올리지 않습니다. 클러스터에는 Kubernetes Secret으로 직접 생성합니다. RDS·Redis 주소, 도메인 같은 환경 값은 Argo CD Application과 GitHub Variables에 두고 저장소에는 예시만 둡니다. AWS 배포는 장기 액세스 키 없이 GitHub Actions OIDC 단기 권한을 사용합니다.

브랜치: `develop`(온프렘 배포) / `main`(AWS 배포). 태그 브랜치 `deploy/onprem`, `deploy/aws`는 workflow만 커밋합니다.