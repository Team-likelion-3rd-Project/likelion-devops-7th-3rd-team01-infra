# 앱 파드용 역할 (EKS Pod Identity, #68).
# 이 역할은 만들기만 한다. 클러스터·서비스 계정과의 연결(aws_eks_pod_identity_association)은 EKS를 만드는 M5-3에서 한다.
# 지금 Bedrock 권한은 EC2 노드 역할(compute 모듈)에 붙어 있어 노드의 모든 파드가 쓸 수 있다. EKS로 옮기면서 이 역할로 대체한다.
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "app_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    # 다른 계정의 EKS가 이 역할을 쓰지 못하게 한다
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "app" {
  name_prefix        = "team01-app-"
  assume_role_policy = data.aws_iam_policy_document.app_trust.json
}
variable "bedrock_model_id" {
  description = "앱이 호출할 수 있는 Bedrock 모델 ID. 이 모델만 허용한다"
  type        = string
  default     = "anthropic.claude-haiku-5-5"
}

data "aws_region" "current" {}

# 호출만 허용: 모델 목록 조회·모델 변경·다른 모델 호출은 허용하지 않는다
data "aws_iam_policy_document" "app_bedrock" {
  statement {
    sid     = "InvokeAllowedModel"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:inference-profile/global.${var.bedrock_model_id}",
      "arn:aws:bedrock:*::foundation-model/${var.bedrock_model_id}",
      "arn:aws:bedrock:::foundation-model/${var.bedrock_model_id}",
    ]
  }
}

resource "aws_iam_role_policy" "app_bedrock" {
  name   = "bedrock-invoke"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_bedrock.json
}