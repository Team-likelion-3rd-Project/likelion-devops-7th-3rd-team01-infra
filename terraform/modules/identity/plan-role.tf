# PR에서 terraform plan을 읽기 전용으로 돌리는 역할 (#65).
# 인프라 레포의 pull_request 이벤트만 맡을 수 있다. 소유자·저장소 ID로 묶어서 이름을 바꿔치기해도 못 쓴다.
locals {
  infra_oidc_sub = "repo:Team-likelion-3rd-Project@336729042/likelion-devops-7th-3rd-team01-infra@1418348985"
}

data "aws_iam_policy_document" "plan_trust" {
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
      values   = ["${local.infra_oidc_sub}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name_prefix        = "team01-infra-plan-"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

# 조회만 가능한 AWS 관리형 정책. 생성·수정·삭제 권한은 없다.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}