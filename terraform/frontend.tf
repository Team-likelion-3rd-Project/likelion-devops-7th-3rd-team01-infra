# 프론트 정적 배포 (M4-12). 리소스는 modules/frontend에 있다 (#65).
# 도메인 이름은 저장소에 두지 않고 terraform.tfvars의 domain_name으로 받는다.

# CloudFront에 붙이는 인증서는 us-east-1에만 만들 수 있다.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "likelion-team01"
      Owner     = "chaneee93"
      Env       = var.environment
      ManagedBy = "terraform"
    }
  }
}

module "frontend" {
  source = "./modules/frontend"

  domain_name              = var.domain_name
  github_oidc_provider_arn = module.identity.github_oidc_provider_arn

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "frontend_bucket_name" {
  description = "프론트 정적 파일 버킷 (GitHub Variables에 등록)"
  value       = module.frontend.bucket_name
}

output "frontend_distribution_id" {
  description = "CloudFront 배포 ID (GitHub Variables에 등록)"
  value       = module.frontend.distribution_id
}

output "frontend_distribution_domain" {
  description = "app.<domain_name> CNAME 대상 (도메인 업체 DNS에 등록)"
  value       = module.frontend.distribution_domain
}

output "frontend_deploy_role_arn" {
  description = "GitHub Actions가 맡을 역할 ARN (GitHub Variables에 등록)"
  value       = module.frontend.deploy_role_arn
}