variable "data_subnet_ids" {
  description = "RDS·Redis 서브넷 그룹에 넣을 데이터 서브넷 ID 목록"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "RDS에 붙일 보안 그룹 ID"
  type        = string
}

variable "redis_security_group_id" {
  description = "Redis에 붙일 보안 그룹 ID"
  type        = string
}

variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "redis_node_type" {
  type = string
}

variable "redis_replicas" {
  type = bool
}