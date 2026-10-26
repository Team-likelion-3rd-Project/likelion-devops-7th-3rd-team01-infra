# 프론트 정적 배포 (M4-12): 비공개 S3 + CloudFront(OAC) + 도메인(app.) + /api/* 프록시 + GitHub Actions 배포 역할.
# 도메인 이름은 저장소에 두지 않고 루트의 terraform.tfvars(domain_name)로 받는다.
data "aws_caller_identity" "current" {}

locals {
  # GitHub이 이 저장소에 붙인 불변(immutable) sub 형식. 소유자·저장소 ID 포함 (프론트 레포 Settings → Actions → OIDC)
  frontend_oidc_sub = "repo:Team-likelion-3rd-Project@336729042/likelion-devops-7th-3rd-team01-frontend@1418340218"
  frontend_host     = "app.${var.domain_name}"
  api_host          = "api.${var.domain_name}"
}

# 빌드 결과물(dist)을 담는 비공개 버킷. S3 주소로 직접 접근하면 거부된다.
# force_destroy: M5 destroy → apply 재생성 시험에서 파일이 들어 있어도 지울 수 있게 한다.
resource "aws_s3_bucket" "frontend" {
  bucket        = "team01-newsbrief-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
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

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# SPA 처리: 확장자가 없는 경로(/, /category/AI 등)만 /index.html로 보낸다.
# 배포 전체에 거는 custom_error_response와 달리 /api 응답은 건드리지 않는다.
resource "aws_cloudfront_function" "spa" {
  name    = "team01-newsbrief-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "SPA: paths without a file extension go to /index.html"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      if (request.uri.indexOf('.') === -1) {
        request.uri = '/index.html';
      }
      return request;
    }
  EOT
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  comment             = "team01 newsbrief frontend"
  aliases             = [local.frontend_host]

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # /api/* 요청을 받는 백엔드(ALB). api.<도메인> DNS가 ALB를 가리켜야 한다.
  origin {
    domain_name = local.api_host
    origin_id   = "api"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  # API는 캐시하지 않고 모든 메서드와 쿠키·헤더를 원본에 전달한다. 브라우저에는 app. 주소 하나로 보인다.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = false
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
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
      identifiers = [var.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.frontend_oidc_sub}:ref:refs/heads/main"]
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