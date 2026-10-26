output "bucket_name" {
  description = "프론트 정적 파일 버킷"
  value       = aws_s3_bucket.frontend.bucket
}

output "distribution_id" {
  description = "CloudFront 배포 ID"
  value       = aws_cloudfront_distribution.frontend.id
}

output "distribution_domain" {
  description = "app.<domain_name> CNAME 대상 (도메인 업체 DNS에 등록)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "deploy_role_arn" {
  description = "GitHub Actions가 맡을 역할 ARN"
  value       = aws_iam_role.frontend_deploy.arn
}