module "compute" {
  source = "./modules/compute"

  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.subnet_ids
  security_group_ids = module.network.security_group_ids

  domain_name          = var.domain_name
  alb_target_ports     = var.alb_target_ports
  cp_instance_type     = var.cp_instance_type
  worker_instance_type = var.worker_instance_type
  k8s_minor            = var.k8s_minor
  k8s_version          = var.k8s_version
  bedrock_policy_name  = var.bedrock_policy_name
}