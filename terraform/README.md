# M3 AWS 네트워크 준비 (#46)

AWS 계정 없이 작성·검증하는 네트워크 초안입니다. 실제 자원은 생성하지 않았습니다.

## 구성

- VPC 10.20.0.0/16, DNS 해석·호스트 이름 활성화
- public 10.20.0.0/24·10.20.1.0/24 → IGW
- app 10.20.10.0/24·10.20.11.0/24 → 같은 AZ NAT (총 2개)
- data 10.20.20.0/24·10.20.21.0/24 → VPC local만 유지
- ALB 80/443 → 앱의 확정 대상/헬스 포트 → MySQL 3306·Redis 6379
- 앱 외부 HTTPS 443 허용. VPC DNS resolver는 AWS의 SG 필터 대상이 아닙니다.

`alb_target_ports`는 기본값을 두지 않았습니다. 현재 온프렘 앱 8080과 Traefik NodePort 30080은 서로 다른 포트입니다. AWS ALB 대상·헬스체크를 확정한 뒤 값을 넣습니다. 리전·AZ도 팀 허용값을 확인해야 합니다.

## 계정 없이 검증

```sh
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

테스트는 mock provider로 네트워크 배치와 입력 제한을 검증합니다. AWS 인증·실제 리소스 생성·RSS 접속 성공을 보증하지 않습니다.

PR 자동 검증은 `.github/workflows/terraform-check.yml`에서 GitHub 호스팅 runner로 실행합니다. 기존 온프렘 runner·배포 workflow와 독립적이며 AWS 자격 증명·OIDC 권한을 요구하지 않습니다. Terraform 버전은 로컬 검증에 사용한 1.16.6으로 고정했습니다. GitHub Actions 실행 성공은 PR 게시 후 확인해야 합니다.

2026-10-21 backend develop의 `Category.java`에서 수집 대상 RSS 8개가 모두 `https://rss.etnews.com/` 주소임을 확인했습니다. 코드의 `app -> HTTPS 443 -> 같은 AZ NAT -> IGW` 경로가 이를 수용합니다. 실제 VPC에서 DNS·HTTPS 통신이 성공했다는 뜻은 아닙니다. HTTP 리디렉션·변경된 RSS 주소가 도입되면 필요한 통신을 다시 확인합니다.

## 계정 수령 후 #51에서 진행

1. #26 계정 권한·MFA·예산, 리전과 AZ, 온프렘 CIDR 중복 확인
2. `terraform.tfvars.example`을 로컬 `terraform.tfvars`로 복사하고 확정값 입력
3. NAT 2개·EIP 2개 비용, 기존 자원 중복 여부 확인
4. 원격 상태·잠금 및 작업자 역할 합의. 초기 로컬 상태로 실제 적용하지 않기
5. 클러스터 제어 평면·노드·Calico·관리 접근 규칙 별도 설계 후 추가
6. 리뷰된 plan 확인 후 승인된 실제 적용, 앱 A/B에서 DNS·외부 HTTPS·NAT EIP 검증

이 보안그룹은 앱 경계 규칙만 다룹니다. kubeadm 노드 통신·CNI·SSM 역할을 포함한 완성 클러스터 설정이 아닙니다. RDS·Redis·EC2·ALB도 이 코드에서 생성하지 않습니다. DB·Redis SG에는 신규 외부 통신 규칙을 두지 않았으며 응답 트래픽은 stateful하게 처리됩니다.

NAT·ALB·ElastiCache는 EC2 정지로 과금이 멈추지 않습니다. 테스트 종료 시 보존 데이터·상태 파일을 분리하고 담당자 확인 후 종료 대상을 정리합니다.

## 출처

- [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [보안그룹 규칙](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)

## 실제 적용 (M4-1, 서울 리전 확정)

1. AWS CLI는 MFA 임시 자격 증명으로 실행한다 (계정에 MFA 강제 정책).
2. 상태 버킷(버전 관리·암호화·공개 차단)을 만든 뒤 `backend.hcl.example` → `backend.hcl`에 이름을 넣는다.
3. `terraform.tfvars.example` → `terraform.tfvars`
4. `terraform init -backend-config=backend.hcl` → `terraform plan -out=tfplan` → 결과 공유 후 `terraform apply tfplan`

`backend.hcl`, `terraform.tfvars`, `tfplan`, 상태 파일은 커밋하지 않는다.
