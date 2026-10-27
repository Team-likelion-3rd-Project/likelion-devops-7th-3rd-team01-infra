output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (역할 신뢰 정책에서 참조)"
  value       = data.aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  description = "PR의 terraform plan이 맡을 읽기 전용 역할 ARN (GitHub Variables에 등록)"
  value       = aws_iam_role.plan.arn
}
output "app_role_arn" {
  description = "앱 파드용 역할 (Bedrock 호출만). M5-3에서 EKS Pod Identity와 연결한다"
  value       = aws_iam_role.app.arn
}
output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}