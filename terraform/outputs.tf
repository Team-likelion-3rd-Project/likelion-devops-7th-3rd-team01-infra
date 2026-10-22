output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids" {
  value = { for k, v in aws_subnet.tier : k => v.id }
}

output "security_group_ids" {
  value = { for k, v in aws_security_group.tier : k => v.id }
}

output "nat_public_ips" {
  value = { for k, v in aws_eip.nat : k => v.public_ip }
}

output "nodes" {
  value = { for k, v in aws_instance.node : k => { id = v.id, private_ip = v.private_ip } }
}
