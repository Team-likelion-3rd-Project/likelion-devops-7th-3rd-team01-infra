# GitHub Actions OIDC 신뢰 등록(이미 있는 것을 참조). 자세한 설명은 modules/identity/main.tf에 있다.
module "identity" {
  source = "./modules/identity"
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (역할 신뢰 정책에서 참조)"
  value       = module.identity.github_oidc_provider_arn
}