# 재생성 절차 (M5-5, #69)

운영 환경을 지웠다가 코드로 다시 만들 때의 절차와 한계를 정리한다.
운영 중이라 실제 destroy는 하지 않았다. 아래는 코드 분석과 plan 확인으로 만든 문서다.

## 1. 현재 근거

| 항목 | 내용 |
|---|---|
| 코드와 운영 일치 | develop 기준 `terraform plan` 결과 `No changes` (10/28 14:02, 김상협 tfvars 기준) |
| EKS 재현 기록 | 10/27 `terraform apply` 후 `k8s/cloud/eks-setup.sh`로 구성 |
| destroy 실행 | 하지 않음 (운영 중). 소요 시간은 측정하지 않았음 |

## 2. 입력값

- `terraform/terraform.tfvars.example`을 복사해 `terraform.tfvars`로 저장한다 (커밋하지 않음).
- `terraform/backend.hcl.example`을 복사해 `backend.hcl`로 저장한다 (커밋하지 않음).
- 운영 값 중 기본값과 다른 것:

| 변수 | 운영 값 | 비고 |
|---|---|---|
| `eks_enabled` | `true` | 기본값 `false` |
| `alb_backend` | `"eks"` | 기본값 `"kubeadm"` |
| `eks_public_access_cidrs` | 작업자 공인 IP | 개인 IP라 저장소에 올리지 않음. 비우면 API가 비공개가 됨 |
| `domain_name` | 서비스 도메인 | 저장소에 올리지 않음 |

- 이 값들이 개인 PC의 파일에만 있으므로, 새 작업자는 팀원에게 받아야 한다.
- CI(`terraform-check`)의 plan 입력은 GitHub 변수 `TFVARS`에서 온다. 저장소가 공개라 Actions 로그도 공개되므로, IP(`eks_public_access_cidrs`)는 변수가 아니라 Secret `EKS_PUBLIC_ACCESS_CIDRS`에 두고 워크플로에서 `TF_VAR_eks_public_access_cidrs`로 넘긴다. 변수 `TFVARS`가 운영 값과 다르면 plan에 EKS 삭제처럼 실제와 다른 변경이 보인다.

## 3. 종료 대상과 보관 대상

**보관 (destroy 대상에서 제외)**
- 상태 파일 버킷, GitHub OIDC 공급자 (Terraform 관리 밖이라 지워지지 않음)
- plan·apply·frontend-deploy 역할과 정책: CI와 apply 권한이다. 같은 상태 파일 안에 있어서 `terraform destroy`를 그대로 쓰면 함께 지워진다. 지우면 역할 이름이 새로 생겨 GitHub Variables의 ARN을 고쳐야 한다. (제외 방법은 아래 "미결정"에 적음)

**데이터 사전 조치**
- RDS: 현재 `skip_final_snapshot = true`, `deletion_protection = false`라서 destroy하면 스냅샷 없이 삭제된다. destroy 전에 스냅샷을 먼저 만든다.
- 복원: 새 DB는 스냅샷에서 복원해야 하는데, 이를 위한 코드 변수는 아직 없다 (미결정).
- 비밀번호는 `manage_master_user_password = true`로 Secrets Manager가 관리한다. 새 DB가 생기면 비밀 ARN이 바뀐다.

**종료 대상**
- 네트워크: VPC, 서브넷, 라우트, IGW, NAT, EIP, 보안그룹과 규칙
- 진입: ALB, 리스너, 대상 그룹
- EKS: 클러스터, 노드 그룹, 애드온, Pod Identity 연결, 노드·클러스터 역할
- 앱 역할 (재생성되며 Pod Identity 연결은 코드로 이어짐)
- ElastiCache, kubeadm 잔재(EC2, 대상 그룹 연결)
- CloudFront, ACM 인증서 2개, 프론트 S3 (`force_destroy = true`). CloudFront는 삭제에 시간이 걸린다.

## 4. 재생성 후 수동 단계

코드만으로 끝나지 않는 부분이다. 이슈 완료 조건 "수동 콘솔 작업 없이"와 충돌한다.

1. **외부 DNS(`n-e.kr`)**: ALB 주소와 CloudFront 도메인이 바뀌면 CNAME을 고쳐야 한다. ACM 검증 레코드는 같은 계정·도메인이면 재사용될 수 있으나 확인하지 않았다.
2. **쿠버네티스 구성**: `k8s/cloud/eks-setup.sh`(Traefik, Secrets, Argo CD, Application)를 실행해야 하며 Secrets는 사람이 입력한다. SSM 복사 방식은 kubeadm 제어 노드가 있어야 가능하므로, kubeadm을 정리한 뒤에는 `read -s` 입력 방식만 쓸 수 있다.
3. **콘솔에서 만든 Bedrock 정책** `newsbrief-bedrock-invoke`: 코드가 이름으로 읽는다(`bedrock_policy_name`). 같은 계정이면 destroy해도 남아 있다. 새 계정에서는 먼저 만들어야 한다.
4. **NAT 고정 IP**: 영향 없음. 이 IP를 허용 목록에 쓰는 곳이 없고, 야간에 `nat_mode = none`으로 EIP까지 지웠다가 아침에 새로 만드는 운영을 이미 해 왔으나 문제가 없었다. (김상협 확인, 10/28)
5. **GitHub Variables**: 위 보관 역할을 지운 경우에만 해당. 역할 ARN을 다시 입력해야 한다.

## 5. 미결정 사항

- plan·apply·frontend-deploy 역할을 destroy에서 제외하는 방법: **별도 상태 파일 분리를 권장하며 지금은 적용하지 않음** (김상협 확인, 10/28). 다른 방법은 `terraform state rm` 후 재가져오기, `-target`으로 삭제 범위 한정.
- RDS 스냅샷 복원용 변수 추가 여부
- 소요 시간은 실제 destroy → apply를 실행할 때 기록한다
