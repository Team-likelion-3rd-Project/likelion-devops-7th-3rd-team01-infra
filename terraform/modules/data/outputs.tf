output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_master_secret_arn" {
  description = "RDS 관리자 비밀번호가 들어 있는 Secrets Manager 비밀 (값은 출력하지 않음)"
  value       = try(aws_db_instance.main.master_user_secret[0].secret_arn, null)
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.main.primary_endpoint_address
}