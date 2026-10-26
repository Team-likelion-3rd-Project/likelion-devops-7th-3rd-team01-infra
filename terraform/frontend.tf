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

# 별칭 provider(aws.us_east_1)가 필요해서 모듈 밖(루트)에 둔다. 모듈에는 인증서 ARN만 넘긴다.
# 검증 CNAME은 ALB 인증서와 같은 값이라 이미 등록되어 있으면 바로 발급된다.
resource "aws_acm_certificate" "frontend" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "frontend" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.frontend.arn
}

module "frontend" {
  source = "./modules/frontend"

  domain_name              = var.domain_name
  certificate_arn          = aws_acm_certificate_validation.frontend.certificate_arn
  github_oidc_provider_arn = module.identity.github_oidc_provider_arn
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