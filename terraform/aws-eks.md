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

## 2단계: 앱 올리고 전환 (10/27 완료)

1. `bash k8s/cloud/eks-setup.sh` : Traefik(NodePort 30080), Secret, Argo CD, Application(newsbrief-aws), Pod Identity·30080 경로 확인
2. `terraform.tfvars`에 `alb_backend = "eks"` → plan(1 change, 리스너) → apply
3. 확인: EKS 대상 그룹 healthy 2개, `https://app.<도메인>/api/news/home` 200, 로그인·질문
4. 기존 kubeadm 앱 내리기 (RDS 연결 한도 때문에 두 클러스터가 동시에 붙으면 Too many connections):
   kubeadm cp에서 `kubectl -n news scale deploy api worker --replicas=0`, `kubectl -n news patch cronjob batch -p '{"spec":{"suspend":true}}'`
5. 되돌리기: kubeadm 앱을 다시 늘린 뒤(api 2, worker 1, batch suspend false) `alb_backend = "kubeadm"` apply

ALB 대상 그룹은 리스너에 연결되기 전에는 헬스체크를 하지 않아 `unused`로 보인다. 전환 전에는 1번 스크립트의 노드 30080 확인으로 대신한다.

## 밤에 끄기 (EKS 있는 동안)

```hcl
eks_node_desired = 0      # 노드 비용 멈춤 (컨트롤 플레인 시간당 비용은 계속 나감)
nat_mode         = "none"
```

apply 후 노드가 지워지지 않고 `Terminating:Wait`에 멈추면 coredns·metrics-server의 PodDisruptionBudget 때문이다
(두 노드를 다 비우므로 옮겨 갈 곳이 없어 drain이 멈춤). 밤에는 서비스가 꺼지므로 그 파드를 직접 지운다.

```bash
kubectl --context team01-eks -n kube-system get pods -o name | grep -E 'coredns|metrics-server' \
  | xargs kubectl --context team01-eks -n kube-system delete
```

아침에는 NAT를 먼저(노드가 이미지를 받아야 함), 그다음 노드를 켠다.

```bash
sed -i '' '/^nat_mode *= *"none"$/d' terraform.tfvars && terraform apply
sed -i '' '/^eks_node_desired *= *0$/d' terraform.tfvars && terraform apply
```

## 비용

- EKS 컨트롤 플레인: 시간당 0.10달러 (끌 수 없음)
- 노드 t3.medium 2대: kubeadm 워커와 같은 수준
- 전환 기간에는 kubeadm 3대와 EKS 노드 2대가 같이 돈다 → 전환 확인 후 kubeadm을 빨리 정리
