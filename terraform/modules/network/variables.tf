variable "availability_zones" {
  description = "승인된 AZ 두 개. 순서는 A, B"
  type        = list(string)
}

variable "environment" {
  description = "Name 태그에 쓰는 환경 이름"
  type        = string
}

variable "nat_mode" {
  description = "per_az: AZ마다 NAT(장애 시나리오 C2) / single: NAT 1개(평소) / none: NAT 없음(작업 안 할 때)"
  type        = string
}

variable "alb_target_ports" {
  description = "ALB가 앱 서버로 보내는 포트 (워커 NodePort)"
  type        = set(number)
}