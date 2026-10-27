# GitHub Actions에서 terraform apply를 돌리는 역할 (#68).
# 브랜치가 아니라 GitHub environment로 묶는다 (기본 브랜치가 develop이라 main 한정은 맞지 않음).
# 사람 승인과 develop 한정은 GitHub environment 설정(Required reviewers, Deployment branches)이 맡는다.
variable "apply_environment_name" {
  description = "apply를 승인하는 GitHub environment 이름"
  type        = string
  default     = "aws-apply"
}

locals {
  apply_iam_prefix = "arn:aws:iam::${data.aws_caller_identity.current.account_id}"
  apply_regions    = distinct([data.aws_region.current.region, "us-east-1"])
}

data "aws_iam_policy_document" "apply_trust" {
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
      values   = ["${local.infra_oidc_sub}:environment:${var.apply_environment_name}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name_prefix          = "team01-infra-apply-"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "apply" {
  # 우리 스택이 쓰는 서비스만 쓰기 허용. 리소스 단위 제한이 어려워 리전으로만 좁힌다.
  statement {
    sid = "ManageStackServices"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "rds:*",
      "elasticache:*",
      "acm:*",
      "cloudfront:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = local.apply_regions
    }
  }

  # RDS·ElastiCache·ALB를 처음 만들 때 AWS가 쓰는 서비스 연결 역할만 허용.
  statement {
    sid       = "CreateServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["${local.apply_iam_prefix}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "elasticache.amazonaws.com",
        "rds.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
      ]
    }
  }

  # IAM 역할 생성·수정은 team01-* 이름만.
  statement {
    sid = "ManageTeamRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = [
      "${local.apply_iam_prefix}:role/team01-*",
      "${local.apply_iam_prefix}:instance-profile/team01-*",
    ]
  }

  # 역할에 붙일 수 있는 관리형 정책을 정해 둔다. AdministratorAccess를 붙여 권한을 키우는 길을 막는다.
  statement {
    sid       = "AttachAllowedPolicies"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["${local.apply_iam_prefix}:role/team01-*"]
    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        "${local.apply_iam_prefix}:policy/newsbrief-*",
      ]
    }
  }

  # 역할을 EC2·EKS에 넘기는 것(PassRole)도 team01-* 이름만.
  statement {
    sid       = "PassTeamRoles"
    actions   = ["iam:PassRole"]
    resources = ["${local.apply_iam_prefix}:role/team01-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "eks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # 우리 버킷(프론트·상태). 다른 팀 버킷은 건드리지 못한다.
  statement {
    sid       = "ManageOwnBuckets"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::team01-newsbrief-*"]
  }

  statement {
    sid       = "ReadPublicAmiParameter"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*::parameter/aws/service/*"]
  }

  # 상태 버킷은 읽기·쓰기만 허용하고 버킷 설정 변경, 삭제, 버전 삭제는 막는다.
  statement {
    sid    = "ProtectStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:DeleteObjectVersion",
    ]
    resources = [
      "arn:aws:s3:::team01-newsbrief-tfstate-*",
      "arn:aws:s3:::team01-newsbrief-tfstate-*/*",
    ]
  }

  # 밖에서 맡는 역할(plan, apply, 프론트 배포)은 apply 역할이 고치지 못한다.
  # 자기 권한을 스스로 키우는 길을 막기 위해서다. 이 역할들의 변경은 로컬 apply로만 한다.
  statement {
    sid    = "ProtectOidcRoles"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:PassRole",
    ]
    resources = [
      "${local.apply_iam_prefix}:role/team01-infra-apply-*",
      "${local.apply_iam_prefix}:role/team01-infra-plan-*",
      "${local.apply_iam_prefix}:role/team01-frontend-deploy-*",
    ]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}