# 프론트 배포 역할 검증 (#68). 실제 AWS 호출 없이 mock provider로 실행한다
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "frontend_deploy_role_contract" {
  command = plan

  module {
    source = "./modules/frontend"
  }

  variables {
    domain_name              = "example.test"
    certificate_arn          = "arn:aws:acm:us-east-1:000000000000:certificate/mock"
    github_oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
  }

  # main 브랜치에서 실행된 workflow만 역할을 쓸 수 있다 (다른 브랜치·PR은 거부)
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.frontend_deploy_trust.statement : (
        length([for c in s.condition : c if c.variable == "token.actions.githubusercontent.com:sub"]) == 1 &&
        alltrue([
          for c in s.condition : (
            c.test == "StringEquals" &&
            alltrue([for v in c.values : endswith(v, ":ref:refs/heads/main") && !strcontains(v, "*")])
          ) if c.variable == "token.actions.githubusercontent.com:sub"
        ])
      )
    ])
    error_message = "프론트 배포 역할은 main 브랜치 한 곳만 정확히 일치(StringEquals)로 허용해야 한다"
  }

  # 토큰 대상(audience)은 AWS STS 하나뿐이다
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.frontend_deploy_trust.statement :
      length([
        for c in s.condition : c
        if c.variable == "token.actions.githubusercontent.com:aud" && length(c.values) == 1 && contains(tolist(c.values), "sts.amazonaws.com")
      ]) == 1
    ])
    error_message = "audience 조건은 sts.amazonaws.com 하나여야 한다"
  }

  # 권한은 S3 업로드·삭제와 CloudFront 무효화뿐이다 (와일드카드 금지)
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.frontend_deploy.statement :
      alltrue([
        for a in s.actions :
        contains(["s3:ListBucket", "s3:PutObject", "s3:DeleteObject", "cloudfront:CreateInvalidation"], a)
      ])
    ])
    error_message = "프론트 배포 역할은 정해진 S3·CloudFront 동작만 허용해야 한다"
  }
}