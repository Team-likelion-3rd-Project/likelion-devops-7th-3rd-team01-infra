locals {
  zones = { a = var.availability_zones[0], b = var.availability_zones[1] }
  # NAT 비용 모드: per_az(AZ마다 1개, 장애 시나리오 C2용) / single(A에만 1개, 평소) / none(작업 안 할 때 NAT 삭제)
  nat_zones = { for k, z in local.zones : k => z if var.nat_mode == "per_az" || (var.nat_mode == "single" && k == "a") }
  subnets = {
    public_a = { cidr = "10.20.0.0/24", zone = "a", tier = "public" }
    public_b = { cidr = "10.20.1.0/24", zone = "b", tier = "public" }
    app_a    = { cidr = "10.20.10.0/24", zone = "a", tier = "app" }
    app_b    = { cidr = "10.20.11.0/24", zone = "b", tier = "app" }
    data_a   = { cidr = "10.20.20.0/24", zone = "a", tier = "data" }
    data_b   = { cidr = "10.20.21.0/24", zone = "b", tier = "data" }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "team01-${var.environment}" }
}

resource "aws_subnet" "tier" {
  for_each                = local.subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = local.zones[each.value.zone]
  map_public_ip_on_launch = false
  tags                    = { Name = "team01-${each.key}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat" {
  for_each = local.nat_zones
  domain   = "vpc"
}

resource "aws_nat_gateway" "zonal" {
  for_each      = local.nat_zones
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.tier["public_${each.key}"].id
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "team01-nat-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table" "app" {
  for_each = local.zones
  vpc_id   = aws_vpc.main.id
}

resource "aws_route" "app_internet" {
  for_each               = { for k, z in local.zones : k => z if var.nat_mode != "none" }
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  # single 모드에서는 B 앱 서브넷도 A의 NAT로 나간다 (AZ 간 전송 요금은 실습 규모에서 미미)
  nat_gateway_id = aws_nat_gateway.zonal[var.nat_mode == "per_az" ? each.key : "a"].id
}

# Local VPC route only; deliberately no data-subnet internet default route.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "tier" {
  for_each       = local.subnets
  subnet_id      = aws_subnet.tier[each.key].id
  route_table_id = each.value.tier == "public" ? aws_route_table.public.id : (each.value.tier == "app" ? aws_route_table.app[each.value.zone].id : aws_route_table.data.id)
}
