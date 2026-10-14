# AI 뉴스 브리핑 - infra

같은 앱을 온프레미스(develop)와 AWS(main)에 배포하기 위한 인프라 저장소입니다.

- 프로젝트 소개·위키·이슈·칸반: [likelion-devops-7th-3rd-team01](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01)
- 앱 저장소: [backend](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-backend) · [frontend](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-frontend)

## 구조

| 경로 | 내용 | 담당 |
|------|------|------|
| `k8s/base/` | 두 환경 공통 매니페스트 (API, 워커, CronJob, 프론트, MySQL, Redis) | 김상협·김차니 |
| `k8s/onprem/` | 온프렘 전용 설정 (local-path, Ingress, COOKIE_SECURE=false) | 김상협 |
| `k8s/cloud/` | AWS 전용 설정 (RDS·ElastiCache 주소, ALB) | 김차니 |
| `onprem/` | VM·kubeadm 클러스터 설정, 애드온 | 김상협 |
| `terraform/` | AWS 환경 | 김차니 |
| `.github/workflows/` | 배포 workflow (온프렘: self-hosted runner, AWS: OIDC) | 김상협·김차니 |

## 비밀 값

비밀번호·API 키·kubeconfig는 이 저장소에 올리지 않습니다. 클러스터에는 Kubernetes Secret으로 직접 생성합니다.

브랜치: `develop`(온프렘 배포) / `main`(AWS 배포)
