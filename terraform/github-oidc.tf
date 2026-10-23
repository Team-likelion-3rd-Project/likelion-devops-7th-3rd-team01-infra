# GitHub Actions가 OIDC로 AWS에 로그인하기 위한 신뢰 등록.
# 계정당 하나만 만들 수 있어 모든 레포(프론트·백엔드)가 공유한다.
# 역할(IAM Role)은 레포별로 각 .tf 파일에서 만들고, 이 provider를 참조한다.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (역할 신뢰 정책에서 참조)"
  value       = aws_iam_openid_connect_provider.github.arn
}