# identity 모듈 앱 파드 역할 검증 (#68). 실제 AWS 호출 없이 모의 provider로 실행한다
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "app_role_contract" {
  command = plan

  module {
    source = "./modules/identity"
  }

  # 신뢰 대상은 EKS Pod Identity 하나뿐이다
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.app_trust.statement :
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["pods.eks.amazonaws.com"])])
    ])
    error_message = "앱 역할은 pods.eks.amazonaws.com만 신뢰해야 한다"
  }

  # 다른 계정의 EKS가 이 역할을 쓰지 못하게 계정 조건이 있다
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.app_trust.statement :
      length([for c in s.condition : c if c.variable == "aws:SourceAccount"]) == 1
    ])
    error_message = "신뢰 정책에 aws:SourceAccount 조건이 있어야 한다"
  }

  # 권한은 모델 호출 두 가지뿐이다
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.app_bedrock.statement :
      s.actions == toset(["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"])
    ])
    error_message = "앱 역할은 Bedrock 모델 호출 외의 동작을 허용하면 안 된다"
  }

  # 리소스는 지정한 모델 하나(와 그 추론 프로필)로 제한된다. 와일드카드 전체 허용 금지
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.app_bedrock.statement :
      alltrue([for r in s.resources : startswith(r, "arn:aws:bedrock:") && endswith(r, var.bedrock_model_id)])
    ])
    error_message = "앱 역할의 리소스는 지정한 모델로만 제한되어야 한다"
  }
}

run "apply_role_contract" {
  command = plan

  module {
    source = "./modules/identity"
  }

  # environment 이름이 정확히 일치할 때만 역할을 쓸 수 있다 (와일드카드 금지)
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.apply_trust.statement : (
        length([for c in s.condition : c if c.variable == "token.actions.githubusercontent.com:sub"]) == 1 &&
        alltrue([
          for c in s.condition : (
            c.test == "StringEquals" &&
            alltrue([for v in c.values : endswith(v, ":environment:${var.apply_environment_name}") && !strcontains(v, "*")])
          ) if c.variable == "token.actions.githubusercontent.com:sub"
        ])
      )
    ])
    error_message = "apply 역할은 정해진 environment 하나만 정확히 일치(StringEquals)로 허용해야 한다"
  }

  # IAM 쓰기 권한은 어디에도 리소스 *로 열지 않는다 (조회용 ReadIam만 예외)
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.apply.statement :
      alltrue([for r in s.resources : r != "*"])
      if coalesce(s.effect, "Allow") == "Allow" && s.sid != "ReadIam" && anytrue([for a in s.actions : startswith(a, "iam:")])
    ])
    error_message = "IAM 쓰기 권한은 리소스를 team01-*로 제한해야 한다"
  }

  # 전체 허용(*, iam:*)은 어디에도 없다
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.apply.statement :
      !contains(s.actions, "*") && !contains(s.actions, "iam:*")
      if coalesce(s.effect, "Allow") == "Allow"
    ])
    error_message = "apply 역할에 전체 허용 권한이 있으면 안 된다"
  }

  # 정책을 붙이는 권한은 허용 목록(iam:PolicyARN 조건)이 있어야 한다
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.apply.statement :
      length([for c in s.condition : c if c.variable == "iam:PolicyARN"]) == 1
      if contains(s.actions, "iam:AttachRolePolicy")
      && coalesce(s.effect, "Allow") == "Allow"
    ])
    error_message = "AttachRolePolicy는 허용할 정책 목록 조건과 함께여야 한다"
  }

  # 밖에서 맡는 역할(apply, plan, 프론트 배포)은 apply 역할이 수정하지 못한다
  assert {
    condition = length([
      for s in data.aws_iam_policy_document.apply.statement : s
      if s.sid == "ProtectOidcRoles" && s.effect == "Deny" && length(s.resources) == 3
    ]) == 1
    error_message = "OIDC로 맡는 역할 3개를 보호하는 Deny가 있어야 한다"
  }


  # 우리 태그가 없는 리소스는 삭제·수정·중지할 수 없다
  assert {
    condition = length([
      for s in data.aws_iam_policy_document.apply.statement : s
      if s.sid == "ProtectOtherTeamResources" && s.effect == "Deny"
      && contains(s.actions, "ec2:Delete*") && contains(s.actions, "rds:Delete*")
      && contains(s.actions, "elasticache:Delete*") && contains(s.actions, "elasticloadbalancing:Delete*")
      && contains(s.actions, "acm:Delete*")
      && length([
        for c in s.condition : c
        if c.variable == "aws:ResourceTag/Project" && c.test == "StringNotEquals"
      ]) == 1
    ]) == 1
    error_message = "태그가 없는 리소스에 대한 삭제·수정·중지 Deny가 있어야 한다"
  }

  # CloudFront도 distribution에 한해 같은 보호가 있다
  assert {
    condition = length([
      for s in data.aws_iam_policy_document.apply.statement : s
      if s.sid == "ProtectOtherTeamDistributions" && s.effect == "Deny"
      && alltrue([for r in s.resources : strcontains(r, ":distribution/")])
    ]) == 1
    error_message = "다른 팀 CloudFront distribution 보호 Deny가 있어야 한다"
  }
}

