resource "aws_security_group" "tier" {
  for_each    = toset(["alb", "app", "db", "redis"])
  name_prefix = "team01-${each.key}-"
  description = "Application tier boundary: ${each.key}"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "sg-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_web" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.tier["alb"].id
  ip_protocol       = "tcp"
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  for_each                     = { for p in var.alb_target_ports : tostring(p) => p }
  security_group_id            = aws_security_group.tier["app"].id
  referenced_security_group_id = aws_security_group.tier["alb"].id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  for_each                     = { for p in var.alb_target_ports : tostring(p) => p }
  security_group_id            = aws_security_group.tier["alb"].id
  referenced_security_group_id = aws_security_group.tier["app"].id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}

resource "aws_vpc_security_group_ingress_rule" "data_from_app" {
  for_each                     = { db = 3306, redis = 6379 }
  security_group_id            = aws_security_group.tier[each.key].id
  referenced_security_group_id = aws_security_group.tier["app"].id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}

resource "aws_vpc_security_group_egress_rule" "app_to_data" {
  for_each                     = { db = 3306, redis = 6379 }
  security_group_id            = aws_security_group.tier["app"].id
  referenced_security_group_id = aws_security_group.tier[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}

# External RSS/SSM/package HTTPS. Plain HTTP is not enabled without a confirmed need.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.tier["app"].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# EC2 Ubuntu 기본 apt 저장소(ap-northeast-2.ec2.archive.ubuntu.com)는 HTTP를 쓴다.
# 노드에 containerd·kubelet 등을 설치할 때 apt update가 실패하지 않도록 80만 추가로 연다.
resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.tier["app"].id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}
