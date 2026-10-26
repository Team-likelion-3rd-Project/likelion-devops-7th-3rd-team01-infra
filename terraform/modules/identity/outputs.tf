output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (역할 신뢰 정책에서 참조)"
  value       = data.aws_iam_openid_connect_provider.github.arn
}