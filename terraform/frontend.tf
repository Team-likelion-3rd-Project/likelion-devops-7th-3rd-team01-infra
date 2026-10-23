# 프론트 정적 배포 (M4-12): 비공개 S3 + CloudFront(OAC) + GitHub Actions 배포 역할.
# 도메인(app.{도메인})과 ACM 인증서는 도메인이 정해지면 별도 PR로 추가한다.
data "aws_caller_identity" "current" {}

locals {
  frontend_repo = "Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-frontend"
}

# 빌드 결과물(dist)을 담는 비공개 버킷. S3 주소로 직접 접근하면 거부된다.
resource "aws_s3_bucket" "frontend" {
  bucket = "team01-newsbrief-frontend-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront만 버킷을 읽을 수 있게 하는 OAC
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "team01-newsbrief-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  comment             = "team01 newsbrief frontend"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  # SPA: 없는 경로는 index.html로 보낸다. 비공개 버킷은 없는 파일에 403을 돌려주므로 403·404 둘 다 처리한다.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  policy     = data.aws_iam_policy_document.frontend_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# GitHub Actions(프론트 레포 main 브랜치)만 이 역할을 쓸 수 있다.
data "aws_iam_policy_document" "frontend_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.frontend_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "frontend_deploy" {
  name_prefix        = "team01-frontend-deploy-"
  assume_role_policy = data.aws_iam_policy_document.frontend_deploy_trust.json
}

# 권한은 이 버킷 업로드와 이 배포의 캐시 무효화만 준다.
data "aws_iam_policy_document" "frontend_deploy" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.frontend.arn]
  }
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }
  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }
}

resource "aws_iam_role_policy" "frontend_deploy" {
  name   = "frontend-deploy"
  role   = aws_iam_role.frontend_deploy.id
  policy = data.aws_iam_policy_document.frontend_deploy.json
}

output "frontend_bucket_name" {
  description = "프론트 정적 파일 버킷 (GitHub Variables에 등록)"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_distribution_id" {
  description = "CloudFront 배포 ID (GitHub Variables에 등록)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_distribution_domain" {
  description = "CloudFront 기본 주소 (도메인 연결 전 확인용)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_deploy_role_arn" {
  description = "GitHub Actions가 맡을 역할 ARN (GitHub Variables에 등록)"
  value       = aws_iam_role.frontend_deploy.arn
}