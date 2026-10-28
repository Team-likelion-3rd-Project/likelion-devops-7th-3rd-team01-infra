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

# 계정을 다른 팀과 같이 쓰므로 ReadOnlyAccess처럼 넓은 정책은 쓰지 않는다.
# 우리 스택이 쓰는 서비스의 조회 권한과 상태 파일 읽기만 허용한다. 목록에 없으면 거부된다.
data "aws_iam_policy_document" "plan_read" {
  # 조회 API는 대부분 리소스 단위로 제한할 수 없어서 리소스는 *로 둔다.
  statement {
    sid = "ReadStackServices"
    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "elasticache:Describe*",
      "elasticache:ListTagsForResource",
      "acm:Describe*",
      "acm:List*",
      "cloudfront:Describe*",
      "cloudfront:Get*",
      "cloudfront:List*",
      "iam:Get*",
      "iam:List*",
    ]
    resources = ["*"]
  }

  # EKS 클러스터·노드 그룹·애드온·Pod Identity 연결·액세스 엔트리 조회 (#67 EKS 전환 이후 plan에 필요).
  # 조회(Describe/List)만 허용한다. 생성·수정·삭제는 apply 역할에서만 한다.
  statement {
    sid = "ReadEks"
    actions = [
      "eks:Describe*",
      "eks:List*",
    ]
    resources = ["*"]
  }

  # 우리 버킷(프론트·상태)의 설정 조회만. 객체 내용은 읽지 못한다.
  statement {
    sid = "ReadOwnBucketSettings"
    actions = [
      "s3:GetBucket*",
      "s3:ListBucket",
      "s3:GetAccelerateConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
    ]
    resources = ["arn:aws:s3:::team01-newsbrief-*"]
  }

  # 상태 파일 하나만 읽는다. 다른 팀 S3 객체는 읽지 못한다.
  statement {
    sid       = "ReadStateFile"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::team01-newsbrief-tfstate-*/aws/terraform.tfstate"]
  }

  # 노드 AMI 조회에 쓰는 AWS 공개 파라미터만.
  statement {
    sid       = "ReadPublicAmiParameter"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*::parameter/aws/service/*"]
  }
}

resource "aws_iam_role_policy" "plan_read" {
  name   = "plan-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_read.json
}
