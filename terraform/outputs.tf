output "vpc_id" {
  value = module.network.vpc_id
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "security_group_ids" {
  value = module.network.security_group_ids
}

output "nat_public_ips" {
  value = module.network.nat_public_ips
}

output "nodes" {
  value = module.compute.nodes
}

output "db_endpoint" {
  value = module.data.db_endpoint
}

output "db_master_secret_arn" {
  description = "RDS 관리자 비밀번호가 들어 있는 Secrets Manager 비밀 (값은 출력하지 않음)"
  value       = module.data.db_master_secret_arn
}

output "redis_endpoint" {
  value = module.data.redis_endpoint
}

output "cert_validation_records" {
  description = "도메인 업체 DNS에 등록할 인증서 검증 CNAME"
  value       = module.compute.cert_validation_records
}

output "alb_dns_name" {
  description = "api.<domain_name> CNAME 대상"
  value       = module.compute.alb_dns_name
}