# frontend.tf의 리소스를 modules/frontend로 옮겼다 (#65).
# 상태의 주소만 바뀌고 리소스는 다시 만들어지지 않는다.
# 모든 환경에서 apply가 끝나면 이 파일은 지워도 된다.
moved {
  from = aws_acm_certificate.frontend
  to   = module.frontend.aws_acm_certificate.frontend
}

moved {
  from = aws_acm_certificate_validation.frontend
  to   = module.frontend.aws_acm_certificate_validation.frontend
}

moved {
  from = aws_s3_bucket.frontend
  to   = module.frontend.aws_s3_bucket.frontend
}

moved {
  from = aws_s3_bucket_public_access_block.frontend
  to   = module.frontend.aws_s3_bucket_public_access_block.frontend
}

moved {
  from = aws_cloudfront_origin_access_control.frontend
  to   = module.frontend.aws_cloudfront_origin_access_control.frontend
}

moved {
  from = aws_cloudfront_function.spa
  to   = module.frontend.aws_cloudfront_function.spa
}

moved {
  from = aws_cloudfront_distribution.frontend
  to   = module.frontend.aws_cloudfront_distribution.frontend
}

moved {
  from = aws_s3_bucket_policy.frontend
  to   = module.frontend.aws_s3_bucket_policy.frontend
}

moved {
  from = aws_iam_role.frontend_deploy
  to   = module.frontend.aws_iam_role.frontend_deploy
}

moved {
  from = aws_iam_role_policy.frontend_deploy
  to   = module.frontend.aws_iam_role_policy.frontend_deploy
}