output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "node_asg_name" {
  description = "ALB 대상 그룹에 붙일 노드 그룹 Auto Scaling 그룹"
  value       = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
