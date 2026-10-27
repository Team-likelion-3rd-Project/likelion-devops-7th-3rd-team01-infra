# Terraform (AWS)

팀 AWS 환경(네트워크·DB·클러스터 노드·ALB·프론트 배포)을 만드는 코드입니다. 리소스는 `modules/` 아래에 있고, 이 폴더의 `*.tf`는 모듈을 연결합니다.

## 모듈 구조

| 모듈 | 내용 |
|------|------|
| `modules/network` | VPC, 서브넷 6개, NAT, 라우트 테이블, 보안 그룹 |
| `modules/data` | RDS(MySQL), ElastiCache(Redis) |
| `modules/compute` | EC2 노드(kubeadm), 노드 IAM 역할, ALB, 인증서 |
| `modules/frontend` | S3, CloudFront, 배포용 IAM 역할. us-east-1 인증서는 별칭 provider가 필요해 루트 `frontend.tf`에 둡니다 |
| `modules/identity` | GitHub OIDC 공급자 참조, PR의 plan용 읽기 전용 역할 |

값은 루트 `variables.tf`가 받고, 모듈끼리 값(서브넷 ID 등)을 주고받을 때는 모듈 출력만 씁니다.

## 네트워크 구성

- VPC 10.20.0.0/16, DNS 해석·호스트 이름 활성화
- public 10.20.0.0/24·10.20.1.0/24 → IGW
- app 10.20.10.0/24·10.20.11.0/24 → 같은 AZ NAT
- data 10.20.20.0/24·10.20.21.0/24 → VPC local만 유지
- ALB 80/443 → 앱의 대상/헬스 포트 → MySQL 3306·Redis 6379
- 앱 외부 HTTPS 443 허용 (RSS 수집용)

`alb_target_ports`는 기본값이 없어서 `terraform.tfvars`에 넣어야 합니다. Traefik NodePort와 앱 컨테이너 포트는 다른 값이므로 NodePort를 넣습니다.

수집 대상 RSS 8개는 모두 `https://rss.etnews.com/` 주소입니다 (2026-10-21 backend develop의 `Category.java` 확인). `app -> HTTPS 443 -> 같은 AZ NAT -> IGW` 경로가 이를 수용합니다. HTTP 리디렉션이나 RSS 주소가 바뀌면 필요한 통신을 다시 확인합니다.

## 상태 파일 (State)

상태 파일은 S3 버킷에 저장합니다. 버킷은 Terraform 밖에서 **수동으로 만든** 것이라 이 코드로 만들거나 지우지 않습니다. (상태를 보관하는 버킷을 그 상태로 관리하면 닭과 달걀 문제가 생깁니다.)

| 설정 | 값 |
|------|----|
| 버킷 이름 | `team01-newsbrief-tfstate-<AWS 계정 ID>` |
| 버전 관리 | 켜짐 (덮어써도 이전 상태로 복구 가능) |
| 암호화 | SSE-S3 |
| 퍼블릭 액세스 | 모두 차단 |
| 잠금 | S3 잠금 파일 (`use_lockfile`). DynamoDB 불필요 |

**동시 실행 방지**: 누가 `plan`이나 `apply`를 실행 중이면 잠금 파일이 생기고, 다른 사람의 실행은 `Error acquiring the state lock`으로 막힙니다. 막혔을 때는 `force-unlock`으로 억지로 풀지 말고, 먼저 실행 중인 사람에게 확인합니다.

## 처음 한 번만 설정

1. AWS CLI는 MFA 임시 자격 증명으로 실행합니다 (계정에 MFA 강제 정책).
2. `backend.hcl.example` → `backend.hcl`에 버킷 이름을 넣습니다.
3. `terraform.tfvars.example` → `terraform.tfvars`에 값을 채웁니다.
4. 초기화하고 계획을 확인합니다.

```sh
terraform init "-backend-config=backend.hcl"
terraform plan
```

`backend.hcl`, `terraform.tfvars`, `tfplan`, 상태 파일은 커밋하지 않습니다. 계정 ID나 키는 코드·이슈·댓글 어디에도 적지 않습니다. (PowerShell에서는 `-backend-config=...` 부분을 따옴표로 감싸야 합니다.)

## apply 규칙

- `apply`는 **한 번에 한 사람**이 합니다. 잠금이 막아 주지만, 실행 전에 팀에 알리는 걸 권장합니다.
- `plan`에 `destroy`나 `replace`가 있으면 이유를 확인하기 전에는 apply하지 않습니다.
- 리소스 위치만 옮기는 리팩터링은 `moved.tf`에 `moved` 블록을 쓰고, `plan`이 `0 to add, 0 to change, 0 to destroy`인지 확인합니다.
- `moved.tf`의 블록은 **모든 환경에서 apply가 끝난 뒤** 지웁니다.

## 계정 없이 검증

```sh
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

테스트는 mock provider로 모듈 배치와 입력 제한을 검증합니다. AWS 인증이나 실제 리소스 생성은 하지 않습니다.

## PR 자동 검사

PR을 올리면 `.github/workflows/terraform-check.yml`이 GitHub 호스팅 runner에서 fmt, init, validate, test를 돌리고, 읽기 전용 AWS 역할로 `plan`까지 돌려 결과를 PR 댓글 하나로 남깁니다. Terraform 버전은 1.16.6으로 고정했습니다.

plan 댓글에는 **리소스 주소와 동작(create/update/delete)만** 올립니다. 이 레포는 공개라 Actions 로그와 댓글이 누구에게나 보이기 때문에, plan 원문은 어디에도 남기지 않습니다.

plan 단계에는 아래 설정이 필요합니다. (레포 Settings → Secrets and variables → Actions → Variables)

| 변수 | 내용 |
|------|------|
| `AWS_PLAN_ROLE_ARN` | `terraform output plan_role_arn` 값. `modules/identity`가 만드는 읽기 전용 역할(우리 스택의 조회 권한과 상태 파일 읽기만 허용)이며, 이 레포의 `pull_request` 실행만 맡을 수 있습니다 |
| `TFVARS` | `terraform.tfvars` 내용 (비밀값 없이 지역·AZ·도메인 등만) |

두 변수가 없거나 포크에서 온 PR이면 plan은 건너뛰고 나머지 검사만 돌립니다.

## 비용 주의

NAT·ALB·ElastiCache·RDS는 EC2를 정지해도 과금이 멈추지 않습니다. 테스트가 끝나면 보존할 데이터와 상태 파일을 분리하고, 담당자 확인 후 종료 대상을 정리합니다.

## 줄바꿈

`.gitattributes`가 `*.tf`, `*.hcl`, `*.sh`를 LF로 고정합니다. Windows에서 `CRLF will be replaced by LF` 경고가 보여도 무해합니다. 에디터는 LF로 저장하세요.

## 출처

- [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [보안그룹 규칙](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)