# M5-3 EKS 클러스터 (#67). 지금 운영 중인 kubeadm 클러스터 옆에 새로 만든다.
# ALB 전환은 compute 모듈의 alb_backend 변수로 한다 (kubeadm ↔ eks, 되돌리기 가능).
# 노드는 kubeadm 노드와 같은 앱 보안 그룹을 붙여 ALB 30080, RDS 3306, Redis 6379 규칙을 그대로 쓴다.

data "aws_default_tags" "current" {}

locals {
  subnets = [var.subnet_ids["app_a"], var.subnet_ids["app_b"]]
}

# ── IAM: 클러스터 역할 ─────────────────────────────────────────
data "aws_iam_policy_document" "cluster_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name_prefix        = "team01-eks-cluster-"
  assume_role_policy = data.aws_iam_policy_document.cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── 클러스터 ────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.eks_version
  role_arn = aws_iam_role.cluster.arn

  # 접근은 EKS access entry로만. 만든 사람(terraform 실행자)에게 관리자 권한을 준다
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = local.subnets
    endpoint_private_access = true
    endpoint_public_access  = length(var.public_access_cidrs) > 0
    public_access_cidrs     = length(var.public_access_cidrs) > 0 ? var.public_access_cidrs : null
  }

  # 표준 지원 기간이 끝나도 유료 연장 지원으로 넘어가지 않게 한다
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# ── IAM: 노드 역할 ──────────────────────────────────────────
data "aws_iam_policy_document" "node_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "team01-eks-node-"
  assume_role_policy = data.aws_iam_policy_document.node_trust.json
}

# Bedrock 권한은 노드가 아니라 앱 파드(Pod Identity)에만 준다
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# ── 노드 그룹 ───────────────────────────────────────────────
# 시작 템플릿으로 앱 보안 그룹을 붙인다. 시작 템플릿에 보안 그룹을 쓰면 EKS가 클러스터 보안 그룹을
# 자동으로 붙이지 않으므로 둘 다 적는다
resource "aws_launch_template" "node" {
  name_prefix = "team01-eks-node-"

  vpc_security_group_ids = [
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
    var.app_security_group_id,
  ]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # ASG가 만드는 인스턴스·볼륨에도 우리 태그(Project 등)를 붙인다 (default_tags는 여기까지 전파되지 않음)
  dynamic "tag_specifications" {
    for_each = ["instance", "volume", "network-interface"]
    content {
      resource_type = tag_specifications.value
      tags          = merge(data.aws_default_tags.current.tags, { Name = "team01-eks-node" })
    }
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "team01-eks-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.subnets
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = [var.node_instance_type]
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired
    min_size     = 0
    max_size     = var.node_max
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ── 애드온 ─────────────────────────────────────────────────
resource "aws_eks_addon" "main" {
  for_each                    = toset(var.addons)
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # coredns·metrics-server는 파드가 뜰 노드가 있어야 Active가 된다
  depends_on = [aws_eks_node_group.main]
}

# ── 앱 파드 → Bedrock (Pod Identity) ───────────────────────
# news 네임스페이스의 default ServiceAccount를 쓰는 api·worker·batch가 앱 역할(Bedrock 호출만)을 받는다.
# kubeadm에서는 노드 역할로 호출했지만, EKS에서는 노드의 다른 파드가 Bedrock을 쓰지 못하게 파드 단위로 준다
resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "news"
  service_account = "default"
  role_arn        = var.app_role_arn

  depends_on = [aws_eks_addon.main]
}
