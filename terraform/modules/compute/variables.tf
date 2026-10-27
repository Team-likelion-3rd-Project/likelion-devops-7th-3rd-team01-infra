variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "network 모듈의 서브넷 ID 맵 (app_a, app_b, public_a, public_b 등)"
  type        = map(string)
}

variable "security_group_ids" {
  description = "network 모듈의 보안 그룹 ID 맵 (alb, app, db, redis)"
  type        = map(string)
}

variable "domain_name" {
  type = string
}

variable "alb_target_ports" {
  type = set(number)
}

variable "cp_instance_type" {
  type = string
}

variable "worker_instance_type" {
  type = string
}

variable "k8s_minor" {
  type = string
}

variable "k8s_version" {
  type = string
}

variable "bedrock_policy_name" {
  type = string
}
variable "eks_enabled" {
  type    = bool
  default = false
}

variable "eks_asg_name" {
  description = "EKS 노드 그룹 Auto Scaling 그룹 이름 (eks_enabled일 때만 쓴다)"
  type        = string
  default     = "none"
}

variable "alb_backend" {
  type    = string
  default = "kubeadm"
  validation {
    condition     = contains(["kubeadm", "eks"], var.alb_backend)
    error_message = "alb_backend must be kubeadm or eks."
  }
}
