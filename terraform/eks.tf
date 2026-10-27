# M5-3 EKS (#67). eks_enabled = true일 때만 만든다. 지금 kubeadm 클러스터는 그대로 두고 옆에 만든다
module "eks" {
  source = "./modules/eks"
  count  = var.eks_enabled ? 1 : 0

  eks_version           = var.eks_version
  subnet_ids            = module.network.subnet_ids
  app_security_group_id = module.network.security_group_ids["app"]
  node_instance_type    = var.eks_node_instance_type
  node_desired          = var.eks_node_desired
  public_access_cidrs   = var.eks_public_access_cidrs
  app_role_arn          = module.identity.app_role_arn
}

output "eks_cluster_name" {
  value = one(module.eks[*].cluster_name)
}
