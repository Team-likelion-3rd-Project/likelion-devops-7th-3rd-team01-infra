# GitHub Actions가 OIDC로 AWS에 로그인하기 위한 신뢰 등록.
# 이 계정에는 이미 만들어져 있다(부트캠프 공용 계정, 다른 팀과 공유).
# 새로 만들지 않고 참조만 하며, 우리 Terraform이 소유·삭제하지 않는다.
# 역할(IAM Role)은 레포별로 각 .tf 파일에서 만들고, 신뢰 정책으로 우리 레포만 허용한다.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN (역할 신뢰 정책에서 참조)"
  value       = data.aws_iam_openid_connect_provider.github.arn
}