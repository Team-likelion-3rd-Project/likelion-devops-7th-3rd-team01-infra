variable "domain_name" {
  description = "서비스 도메인. app.<domain_name>은 프론트, api.<domain_name>은 백엔드(ALB)를 가리킨다"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (배포 역할 신뢰 정책에서 참조)"
  type        = string
}