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