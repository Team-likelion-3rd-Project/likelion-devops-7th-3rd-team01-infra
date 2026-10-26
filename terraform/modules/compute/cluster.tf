# M4-2 EC2 kubeadm 클러스터 (온프렘과 같은 구성: control plane 1, worker 2)
# 노드는 앱 서브넷(공인 IP 없음)에 두고 SSM으로만 접속한다. SSH 포트는 열지 않는다.
# kubeadm init/join은 노드가 뜬 뒤 SSM으로 직접 실행한다 (aws-cluster.md).

locals {
  nodes = {
    cp       = { subnet = "app_a", type = var.cp_instance_type }
    worker-a = { subnet = "app_a", type = var.worker_instance_type }
    worker-b = { subnet = "app_b", type = var.worker_instance_type }
  }
}

# Ubuntu 24.04 공식 AMI. 새 AMI가 나와도 노드를 다시 만들지 않도록 lifecycle에서 무시한다
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# 노드끼리는 모든 통신 허용 (API 서버 6443, kubelet 10250, Calico VXLAN 4789/udp, NodePort, 파드 간 통신)
resource "aws_vpc_security_group_ingress_rule" "app_self" {
  security_group_id            = var.security_group_ids["app"]
  referenced_security_group_id = var.security_group_ids["app"]
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "app_self" {
  security_group_id            = var.security_group_ids["app"]
  referenced_security_group_id = var.security_group_ids["app"]
  ip_protocol                  = "-1"
}

resource "aws_instance" "node" {
  for_each                    = local.nodes
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = each.value.type
  subnet_id                   = var.subnet_ids[each.value.subnet]
  vpc_security_group_ids      = [var.security_group_ids["app"]]
  iam_instance_profile        = aws_iam_instance_profile.node.name
  associate_public_ip_address = false
  user_data = templatefile("${path.module}/node-init.sh", {
    hostname    = "aws-${each.key}"
    k8s_minor   = var.k8s_minor
    k8s_version = var.k8s_version
  })

  metadata_options {
    http_tokens = "required"
    # 파드(컨테이너) 안에서도 노드 역할로 Bedrock을 호출하려면 2가 필요하다 (기본 1이면 컨테이너에서 막힘)
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = { Name = "team01-aws-${each.key}", Role = each.key == "cp" ? "control-plane" : "worker" }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
