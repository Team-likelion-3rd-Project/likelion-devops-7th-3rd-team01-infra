variable "aws_region" {
  description = "Team-approved region; deliberately no default."
  type        = string
}

variable "availability_zones" {
  description = "Two approved AZ names, ordered A then B."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Provide exactly two distinct AZ names."
  }
}

variable "environment" {
  type    = string
  default = "practice"
}

variable "alb_target_ports" {
  description = "Confirmed worker NodePort target and health ports; not the container port."
  type        = set(number)
  validation {
    condition     = length(var.alb_target_ports) > 0 && alltrue([for p in var.alb_target_ports : p >= 1 && p <= 65535 && floor(p) == p])
    error_message = "Supply at least one confirmed integer TCP port (1-65535)."
  }
}

variable "nat_mode" {
  description = "per_az: AZ마다 NAT(장애 시나리오 C2) / single: NAT 1개(평소) / none: NAT 없음(작업 안 할 때)"
  type        = string
  default     = "single"
  validation {
    condition     = contains(["per_az", "single", "none"], var.nat_mode)
    error_message = "nat_mode must be per_az, single, or none."
  }
}

variable "cp_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  # AWS에는 MySQL·Redis·프론트 파드가 없어 온프렘 워커보다 가볍다. 부족하면 t3.large로 올린다
  type    = string
  default = "t3.medium"
}

variable "k8s_minor" {
  description = "pkgs.k8s.io 저장소 버전 (온프렘과 동일)"
  type        = string
  default     = "v1.35"
}

variable "k8s_version" {
  description = "kubelet·kubeadm·kubectl 버전 (온프렘과 동일)"
  type        = string
  default     = "1.35.9"
}

variable "bedrock_policy_name" {
  description = "노드 역할에 붙일 Bedrock 호출 정책 이름. 빈 값이면 붙이지 않는다"
  type        = string
  default     = "newsbrief-bedrock-invoke"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  description = "RDS Multi-AZ. 평소 false, 장애 시나리오 C3 시험 때 true"
  type        = bool
  default     = false
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "redis_replicas" {
  description = "Redis 복제본 + 자동 장애 전환. 평소 false, 장애 시나리오 C5 시험 때 true"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "서비스 도메인 (예: news.example.com). 접속 주소라 저장소에 두지 않고 terraform.tfvars에 넣는다"
  type        = string
}
