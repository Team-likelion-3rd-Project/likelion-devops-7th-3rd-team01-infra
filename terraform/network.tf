# VPC·서브넷·NAT·라우팅·보안그룹. 리소스는 modules/network에 있다 (#65).
module "network" {
  source = "./modules/network"

  availability_zones = var.availability_zones
  environment        = var.environment
  nat_mode           = var.nat_mode
  alb_target_ports   = var.alb_target_ports
}