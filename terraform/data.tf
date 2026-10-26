module "data" {
  source = "./modules/data"

  data_subnet_ids         = [module.network.subnet_ids["data_a"], module.network.subnet_ids["data_b"]]
  db_security_group_id    = module.network.security_group_ids["db"]
  redis_security_group_id = module.network.security_group_ids["redis"]

  db_instance_class = var.db_instance_class
  db_multi_az       = var.db_multi_az
  redis_node_type   = var.redis_node_type
  redis_replicas    = var.redis_replicas
}