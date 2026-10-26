mock_provider "aws" {
  # 프론트 배포(frontend.tf)용 가짜 데이터
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:function/team01-newsbrief-spa-rewrite" }
  }
  mock_resource "aws_route_table" {
    defaults = { route = [] }
  }
  # 가짜 값이라도 ARN 형식이어야 정책 연결 검사를 통과한다
  mock_data "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/newsbrief-bedrock-invoke" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_db_instance" {
    defaults = { address = "team01-news.mock.ap-northeast-2.rds.amazonaws.com" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/mock" }
  }
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/mock" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/team01-alb/mock", dns_name = "team01-alb-mock.ap-northeast-2.elb.amazonaws.com" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/team01-traefik-web/mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/team01-k8s-node-mock" }
  }
}

# CloudFront용 us-east-1 인증서 (frontend.tf의 provider alias)
mock_provider "aws" {
  alias = "us_east_1"
  mock_resource "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock" }
  }
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock" }
  }
}

variables {
  aws_region         = "ap-northeast-2"
  availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]
  alb_target_ports   = [30080]
  domain_name        = "news.example.com"
}

run "network_contract" {
  # Mock apply only: no AWS credentials, API calls, or real resources.
  command = apply
  variables {
    nat_mode = "per_az"
  }

  assert {
    condition     = length(aws_subnet.tier) == 6 && length(aws_nat_gateway.zonal) == 2
    error_message = "Keep six subnets and one NAT in each of the two AZs."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.tier : s.map_public_ip_on_launch == false])
    error_message = "No subnet should auto-assign public IPv4 addresses."
  }
  assert {
    condition     = alltrue([for k, r in aws_route.app_internet : r.nat_gateway_id == aws_nat_gateway.zonal[k].id])
    error_message = "Each app subnet must use its own AZ NAT."
  }
  assert {
    condition = alltrue([for k, z in local.zones :
      aws_nat_gateway.zonal[k].subnet_id == aws_subnet.tier["public_${k}"].id &&
      aws_subnet.tier["app_${k}"].availability_zone == aws_subnet.tier["public_${k}"].availability_zone &&
      aws_route_table_association.tier["app_${k}"].route_table_id == aws_route_table.app[k].id
    ])
    error_message = "App route-table association and public NAT placement must match each AZ."
  }
  assert {
    condition     = aws_route.public_internet.gateway_id == aws_internet_gateway.main.id && alltrue([for k in ["a", "b"] : aws_route_table_association.tier["public_${k}"].route_table_id == aws_route_table.public.id])
    error_message = "Both public subnets must use the IGW route table."
  }
  assert {
    condition     = aws_route_table_association.tier["data_a"].route_table_id == aws_route_table.data.id && aws_route_table_association.tier["data_b"].route_table_id == aws_route_table.data.id && length(aws_route_table.data.route) == 0
    error_message = "Data subnets must share the isolated route table with no added routes."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.data_from_app["db"].from_port == 3306 && aws_vpc_security_group_ingress_rule.data_from_app["redis"].from_port == 6379 && alltrue([for r in aws_vpc_security_group_ingress_rule.data_from_app : r.referenced_security_group_id == aws_security_group.tier["app"].id])
    error_message = "MySQL/Redis ingress must originate only from app SG."
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.app_from_alb : r.referenced_security_group_id == aws_security_group.tier["alb"].id && contains(var.alb_target_ports, r.from_port) && r.from_port == r.to_port]) && aws_vpc_security_group_egress_rule.app_https.from_port == 443 && aws_vpc_security_group_egress_rule.app_https.to_port == 443
    error_message = "App ingress must be ALB-only; external HTTPS must remain available for RSS."
  }
}

run "reject_duplicate_azs" {
  command = plan
  variables {
    availability_zones = ["ap-northeast-2a", "ap-northeast-2a"]
  }
  expect_failures = [var.availability_zones]
}

run "reject_invalid_port" {
  command = plan
  variables {
    alb_target_ports = [0]
  }
  expect_failures = [var.alb_target_ports]
}

run "reject_empty_ports" {
  command = plan
  variables {
    alb_target_ports = []
  }
  expect_failures = [var.alb_target_ports]
}

run "reject_fractional_port" {
  command = plan
  variables {
    alb_target_ports = [30080.5]
  }
  expect_failures = [var.alb_target_ports]
}

run "reject_out_of_range_port" {
  command = plan
  variables {
    alb_target_ports = [65536]
  }
  expect_failures = [var.alb_target_ports]
}

run "cluster_contract" {
  # Mock apply only: EC2 nodes, IAM role, node-to-node rules.
  command = apply

  assert {
    condition     = length(aws_instance.node) == 3 && alltrue([for n in aws_instance.node : n.associate_public_ip_address == false])
    error_message = "Three nodes without public IPv4."
  }
  assert {
    condition     = aws_instance.node["cp"].subnet_id == aws_subnet.tier["app_a"].id && aws_instance.node["worker-a"].subnet_id == aws_subnet.tier["app_a"].id && aws_instance.node["worker-b"].subnet_id == aws_subnet.tier["app_b"].id
    error_message = "Nodes must sit in the private app subnets, workers split across AZs."
  }
  assert {
    condition     = alltrue([for n in aws_instance.node : n.metadata_options[0].http_tokens == "required" && n.metadata_options[0].http_put_response_hop_limit == 2])
    error_message = "IMDSv2 required, hop limit 2 so pods can use the node role."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_self.referenced_security_group_id == aws_security_group.tier["app"].id && aws_vpc_security_group_ingress_rule.app_self.ip_protocol == "-1"
    error_message = "Nodes in the app SG must reach each other."
  }
}

run "single_nat" {
  command = apply
  variables {
    nat_mode = "single"
  }
  assert {
    condition     = length(aws_nat_gateway.zonal) == 1 && length(aws_eip.nat) == 1 && alltrue([for r in aws_route.app_internet : r.nat_gateway_id == aws_nat_gateway.zonal["a"].id]) && length(aws_route.app_internet) == 2
    error_message = "Single mode: one NAT in AZ A serving both app subnets."
  }
}

run "no_nat" {
  command = apply
  variables {
    nat_mode = "none"
  }
  assert {
    condition     = length(aws_nat_gateway.zonal) == 0 && length(aws_eip.nat) == 0 && length(aws_route.app_internet) == 0
    error_message = "None mode: no NAT, EIP, or app default route."
  }
}

run "reject_bad_nat_mode" {
  command = plan
  variables {
    nat_mode = "two"
  }
  expect_failures = [var.nat_mode]
}

run "data_contract" {
  command = apply

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false && aws_db_instance.main.storage_encrypted && aws_db_instance.main.manage_master_user_password && contains(aws_db_instance.main.vpc_security_group_ids, aws_security_group.tier["db"].id)
    error_message = "RDS must be private, encrypted, password managed by Secrets Manager, db SG only."
  }
  assert {
    condition     = aws_db_instance.main.multi_az == false && aws_elasticache_replication_group.main.num_cache_clusters == 1
    error_message = "Default to single-AZ RDS and single Redis node for cost."
  }
  assert {
    condition     = toset(aws_db_subnet_group.main.subnet_ids) == toset([aws_subnet.tier["data_a"].id, aws_subnet.tier["data_b"].id])
    error_message = "DB must sit in the data subnets."
  }
}

run "alb_contract" {
  command = apply

  assert {
    condition     = aws_lb.main.internal == false && toset(aws_lb.main.subnets) == toset([aws_subnet.tier["public_a"].id, aws_subnet.tier["public_b"].id]) && contains(aws_lb.main.security_groups, aws_security_group.tier["alb"].id)
    error_message = "ALB must be internet-facing in the public subnets with the ALB SG."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.worker) == 2 && !contains(keys(aws_lb_target_group_attachment.worker), "cp") && aws_lb_target_group.traefik.port == 30080
    error_message = "Only the two workers on the Traefik NodePort are ALB targets."
  }
  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && aws_lb_listener.https.protocol == "HTTPS"
    error_message = "HTTP must redirect to HTTPS."
  }
}

# frontend.tf의 리소스는 modules/frontend로 옮겼다. 모듈을 직접 대상으로 검사한다.
run "frontend_contract" {
  command = apply

  module {
    source = "./modules/frontend"
  }

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    domain_name              = "news.example.com"
    github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = aws_s3_bucket.frontend.force_destroy == true
    error_message = "Frontend bucket must allow destroy with files for the M5 recreate test."
  }
  assert {
    condition     = toset(aws_cloudfront_distribution.frontend.aliases) == toset(["app.news.example.com"])
    error_message = "CloudFront must serve the app. host only."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.frontend.custom_error_response) == 0
    error_message = "SPA fallback must use the CloudFront Function, not distribution-wide error responses."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.frontend.ordered_cache_behavior) == 1 && aws_cloudfront_distribution.frontend.ordered_cache_behavior[0].path_pattern == "/api/*"
    error_message = "Only /api/* goes to the API origin."
  }
}

# 루트가 모듈을 올바르게 연결했는지 본다. 출력 이름은 GitHub Variables 등록에 쓰이므로 그대로여야 한다.
run "frontend_wiring" {
  command = apply

  assert {
    condition     = output.frontend_bucket_name == "team01-newsbrief-frontend-123456789012"
    error_message = "Root output must expose the frontend bucket from the module."
  }
}