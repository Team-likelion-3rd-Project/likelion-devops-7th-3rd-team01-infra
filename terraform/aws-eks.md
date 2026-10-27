# EKS 전환 (M5-3)

지금 운영 중인 kubeadm 클러스터는 그대로 두고 옆에 EKS를 만든 뒤, ALB 대상만 바꿔 전환한다. 문제가 생기면 대상만 되돌린다.

```
              ┌─ 대상 그룹 team01-traefik-web: kubeadm 워커 2대 ─ Traefik 30080   (alb_backend = kubeadm)
ALB ─ HTTPS ─┤
              └─ 대상 그룹 team01-eks-web:     EKS 노드 그룹(ASG) ─ Traefik 30080 (alb_backend = eks)
```

| 항목 | 내용 |
|---|---|
| 클러스터 | `team01-eks`, 서브넷 app_a·app_b, access entry(API) 방식, 만든 사람에게 관리자 권한 |
| API 엔드포인트 | private 항상 켬. public은 `eks_public_access_cidrs`에 적은 IP만 (비우면 VPC 안에서만) |
| 노드 | 관리형 노드 그룹 AL2023, t3.medium 2대(최대 3). kubeadm 노드와 같은 앱 보안 그룹 → ALB 30080, RDS, Redis 규칙 그대로 |
| 애드온 | vpc-cni, kube-proxy, coredns, eks-pod-identity-agent, metrics-server |
| Bedrock | 노드 역할이 아니라 앱 파드만(Pod Identity): news 네임스페이스 default SA ↔ identity 모듈의 앱 역할(모델 하나 호출만) |
| 지원 정책 | STANDARD (유료 연장 지원으로 자동으로 넘어가지 않음) |

## 1단계: 클러스터 만들기 (사이트 영향 없음)

```bash
# 지원 버전 확인 (eks_version 기본값 1.35가 목록에 있는지)
aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion' --output text

# 내 공인 IP (EKS API 공개 엔드포인트 허용용)
curl -s https://checkip.amazonaws.com
```

`terraform.tfvars`(저장소에 올리지 않음)에 추가

```hcl
eks_enabled             = true
eks_public_access_cidrs = ["<내 IP>/32"]
# alb_backend = "kubeadm"   # 기본값. 전환 전까지 그대로
```

```bash
terraform plan    # 추가만 있어야 함: EKS 클러스터·노드 그룹·IAM 역할·애드온·대상 그룹 등. destroy 0
terraform apply   # 클러스터 15분 안팎 + 노드 그룹 5분 안팎

aws eks update-kubeconfig --name team01-eks --alias team01-eks
kubectl --context team01-eks get nodes                 # 2대 Ready
kubectl --context team01-eks get pods -n kube-system   # coredns·metrics-server 등 Running
```

IP가 바뀌면(장소 이동) `eks_public_access_cidrs`만 고쳐서 apply한다.

## 2단계: 앱 올리고 전환 (다음 작업)

1. EKS에 Traefik(NodePort 30080), Argo CD 설치
2. news 네임스페이스 Secret(mysql-secret, app-secret, ghcr-pull) 생성. 값은 채팅·저장소에 두지 않고 `read -s`로 입력
3. Argo CD Application(newsbrief-aws): 차트 + values-aws.yaml + 태그. DB·Redis 주소, 화면 주소, AI 모드는 저장소가 아니라 Application에 직접 넣는다
4. EKS 대상 그룹 헬스체크 healthy 확인 → `alb_backend = "eks"` apply → 사이트·로그인·질문 확인
5. 이상 있으면 `alb_backend = "kubeadm"` apply로 즉시 되돌림
6. 며칠 안정적이면 kubeadm EC2 정리

## 밤에 끄기 (EKS 있는 동안)

```hcl
eks_node_desired = 0      # 노드 비용 멈춤 (컨트롤 플레인 시간당 비용은 계속 나감)
nat_mode         = "none"
```

아침에는 `eks_node_desired = 2`, `nat_mode` 기본값으로 되돌려 apply (NAT가 있어야 노드가 이미지를 받는다).

## 비용

- EKS 컨트롤 플레인: 시간당 0.10달러 (끌 수 없음)
- 노드 t3.medium 2대: kubeadm 워커와 같은 수준
- 전환 기간에는 kubeadm 3대와 EKS 노드 2대가 같이 돈다 → 전환 확인 후 kubeadm을 빨리 정리
