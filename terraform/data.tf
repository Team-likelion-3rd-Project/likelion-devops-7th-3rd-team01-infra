# M4-3 운영 DB·캐시 (데이터 서브넷, 앱 SG에서만 접근)
# 실습 비용을 줄이려고 기본은 단일 AZ·노드 1개. 장애 시나리오 C3·C5 시험 때만 이중화를 켠다.

resource "aws_db_subnet_group" "main" {
  name_prefix = "team01-db-"
  subnet_ids  = [module.network.subnet_ids["data_a"], module.network.subnet_ids["data_b"]]
}

# 온프렘 MySQL(custom.cnf)과 같은 설정: utf8mb4, UTC, 한국어 전문 검색용 ngram 2
resource "aws_db_parameter_group" "mysql" {
  name_prefix = "team01-mysql84-"
  family      = "mysql8.4"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
  parameter {
    name  = "time_zone"
    value = "UTC"
  }
  parameter {
    name         = "ngram_token_size"
    value        = "2"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier_prefix = "team01-news-"
  engine            = "mysql"
  engine_version    = "8.4"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  db_name           = "news"
  username          = "admin"
  # 비밀번호는 Terraform이 아니라 Secrets Manager가 만들고 보관한다 (상태 파일·코드에 남지 않음)
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.main.name
  parameter_group_name        = aws_db_parameter_group.mysql.name
  vpc_security_group_ids      = [module.network.security_group_ids["db"]]
  publicly_accessible         = false
  multi_az                    = var.db_multi_az
  backup_retention_period     = 7
  apply_immediately           = true
  deletion_protection         = false
  # 실습 환경: destroy 시 최종 스냅샷을 남기지 않는다. 남길 데이터가 생기면 false로 바꾼다
  skip_final_snapshot = true
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "team01-redis"
  subnet_ids = [module.network.subnet_ids["data_a"], module.network.subnet_ids["data_b"]]
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "team01-redis"
  description                = "news api cache"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_replicas ? 2 : 1
  automatic_failover_enabled = var.redis_replicas
  multi_az_enabled           = var.redis_replicas
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [module.network.security_group_ids["redis"]]
  at_rest_encryption_enabled = true
  # 앱(Spring)이 평문 Redis로 접속한다. 데이터 서브넷 + 앱 SG에서만 접근 가능
  transit_encryption_enabled = false
  apply_immediately          = true
}
