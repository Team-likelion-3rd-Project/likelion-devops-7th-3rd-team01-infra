# frontend.tf의 리소스를 modules/frontend로 옮겼다 (#65).
# 상태의 주소만 바뀌고 리소스는 다시 만들어지지 않는다.
# 모든 환경에서 apply가 끝나면 이 파일은 지워도 된다.
moved {
  from = aws_s3_bucket.frontend
  to   = module.frontend.aws_s3_bucket.frontend
}

moved {
  from = aws_s3_bucket_public_access_block.frontend
  to   = module.frontend.aws_s3_bucket_public_access_block.frontend
}

moved {
  from = aws_cloudfront_origin_access_control.frontend
  to   = module.frontend.aws_cloudfront_origin_access_control.frontend
}

moved {
  from = aws_cloudfront_function.spa
  to   = module.frontend.aws_cloudfront_function.spa
}

moved {
  from = aws_cloudfront_distribution.frontend
  to   = module.frontend.aws_cloudfront_distribution.frontend
}

moved {
  from = aws_s3_bucket_policy.frontend
  to   = module.frontend.aws_s3_bucket_policy.frontend
}

moved {
  from = aws_iam_role.frontend_deploy
  to   = module.frontend.aws_iam_role.frontend_deploy
}

moved {
  from = aws_iam_role_policy.frontend_deploy
  to   = module.frontend.aws_iam_role_policy.frontend_deploy
}


# network 모듈 이동
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_subnet.tier
  to   = module.network.aws_subnet.tier
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_eip.nat
  to   = module.network.aws_eip.nat
}

moved {
  from = aws_nat_gateway.zonal
  to   = module.network.aws_nat_gateway.zonal
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table.app
  to   = module.network.aws_route_table.app
}

moved {
  from = aws_route_table.data
  to   = module.network.aws_route_table.data
}

moved {
  from = aws_route.public_internet
  to   = module.network.aws_route.public_internet
}

moved {
  from = aws_route.app_internet
  to   = module.network.aws_route.app_internet
}

moved {
  from = aws_route_table_association.tier
  to   = module.network.aws_route_table_association.tier
}

moved {
  from = aws_security_group.tier
  to   = module.network.aws_security_group.tier
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_web
  to   = module.network.aws_vpc_security_group_ingress_rule.alb_web
}

moved {
  from = aws_vpc_security_group_ingress_rule.app_from_alb
  to   = module.network.aws_vpc_security_group_ingress_rule.app_from_alb
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_app
  to   = module.network.aws_vpc_security_group_egress_rule.alb_to_app
}

moved {
  from = aws_vpc_security_group_ingress_rule.data_from_app
  to   = module.network.aws_vpc_security_group_ingress_rule.data_from_app
}

moved {
  from = aws_vpc_security_group_egress_rule.app_to_data
  to   = module.network.aws_vpc_security_group_egress_rule.app_to_data
}

moved {
  from = aws_vpc_security_group_egress_rule.app_https
  to   = module.network.aws_vpc_security_group_egress_rule.app_https
}

moved {
  from = aws_vpc_security_group_egress_rule.app_http
  to   = module.network.aws_vpc_security_group_egress_rule.app_http
}

# data 모듈 이동
moved {
  from = aws_db_subnet_group.main
  to   = module.data.aws_db_subnet_group.main
}

moved {
  from = aws_db_parameter_group.mysql
  to   = module.data.aws_db_parameter_group.mysql
}

moved {
  from = aws_db_instance.main
  to   = module.data.aws_db_instance.main
}

moved {
  from = aws_elasticache_subnet_group.main
  to   = module.data.aws_elasticache_subnet_group.main
}

moved {
  from = aws_elasticache_replication_group.main
  to   = module.data.aws_elasticache_replication_group.main
}

# compute 모듈 이동
moved {
  from = aws_acm_certificate.main
  to   = module.compute.aws_acm_certificate.main
}

moved {
  from = aws_acm_certificate_validation.main
  to   = module.compute.aws_acm_certificate_validation.main
}

moved {
  from = aws_lb.main
  to   = module.compute.aws_lb.main
}

moved {
  from = aws_lb_target_group.traefik
  to   = module.compute.aws_lb_target_group.traefik
}

moved {
  from = aws_lb_target_group_attachment.worker
  to   = module.compute.aws_lb_target_group_attachment.worker
}

moved {
  from = aws_lb_listener.http
  to   = module.compute.aws_lb_listener.http
}

moved {
  from = aws_lb_listener.https
  to   = module.compute.aws_lb_listener.https
}

moved {
  from = aws_vpc_security_group_ingress_rule.app_self
  to   = module.compute.aws_vpc_security_group_ingress_rule.app_self
}

moved {
  from = aws_vpc_security_group_egress_rule.app_self
  to   = module.compute.aws_vpc_security_group_egress_rule.app_self
}

moved {
  from = aws_instance.node
  to   = module.compute.aws_instance.node
}

moved {
  from = aws_iam_role.node
  to   = module.compute.aws_iam_role.node
}

moved {
  from = aws_iam_role_policy_attachment.ssm
  to   = module.compute.aws_iam_role_policy_attachment.ssm
}

moved {
  from = aws_iam_role_policy_attachment.bedrock
  to   = module.compute.aws_iam_role_policy_attachment.bedrock
}

moved {
  from = aws_iam_instance_profile.node
  to   = module.compute.aws_iam_instance_profile.node
}