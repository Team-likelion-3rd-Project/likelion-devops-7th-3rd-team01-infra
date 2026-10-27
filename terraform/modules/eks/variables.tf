variable "cluster_name" {
  type    = string
  default = "team01-eks"
}

variable "eks_version" {
  description = "EKS 쿠버네티스 버전. 적용 전 aws eks describe-cluster-versions로 지원 여부 확인"
  type        = string
}

variable "subnet_ids" {
  description = "network 모듈의 서브넷 ID 맵. 클러스터·노드는 app_a, app_b(공인 IP 없음)에 둔다"
  type        = map(string)
}

variable "app_security_group_id" {
  description = "앱 보안 그룹. 노드에 붙여서 ALB(30080)·RDS·Redis 규칙을 kubeadm 노드와 똑같이 쓴다"
  type        = string
}

variable "node_instance_type" {
  type = string
}

variable "node_desired" {
  description = "노드 수. 밤에 0으로 두면 노드 비용이 멈춘다 (컨트롤 플레인 비용은 계속 나감)"
  type        = number
}

variable "node_max" {
  type    = number
  default = 3
}

variable "public_access_cidrs" {
  description = "API 서버 공개 엔드포인트 허용 IP. 비우면 공개 엔드포인트를 끄고 VPC 안에서만 접속"
  type        = list(string)
}

variable "app_role_arn" {
  description = "앱 파드용 Bedrock 역할 (identity 모듈). news 네임스페이스 default SA에 Pod Identity로 연결"
  type        = string
}

variable "addons" {
  description = "EKS 관리형 애드온. 노드가 있어야 뜨는 것은 노드 그룹 뒤에 만든다"
  type        = list(string)
  default     = ["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent", "metrics-server"]
}
