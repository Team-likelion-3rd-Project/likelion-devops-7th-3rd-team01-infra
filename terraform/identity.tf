# GitHub Actions OIDC 신뢰 등록(이미 있는 것을 참조). 자세한 설명은 modules/identity/main.tf에 있다.
module "identity" {
  source = "./modules/identity"
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (역할 신뢰 정책에서 참조)"
  value       = module.identity.github_oidc_provider_arn
}

output "plan_role_arn" {
  description = "PR의 terraform plan이 맡을 읽기 전용 역할 ARN (GitHub Variables AWS_PLAN_ROLE_ARN에 등록)"
  value       = module.identity.plan_role_arn
}