# M4-4 ALB·HTTPS. api.<domain_name> → ALB(HTTPS) → 워커 Traefik NodePort 30080 → api
# 인증서는 domain_name과 *.domain_name 하나로 발급하고, 외부 DNS(도메인 업체)에 검증 CNAME을 직접 넣는다.
# 적용 순서 (aws-alb.md): 1) 인증서만 생성 → 2) 검증 CNAME 등록 → 3) 전체 apply

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 검증 CNAME이 등록되어 인증서가 발급될 때까지 기다린다
resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn
}

resource "aws_lb" "main" {
  name                       = "team01-alb"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = [module.network.subnet_ids["public_a"], module.network.subnet_ids["public_b"]]
  security_groups            = [module.network.security_group_ids["alb"]]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "traefik" {
  name     = "team01-traefik-web"
  port     = tolist(var.alb_target_ports)[0]
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id

  # Traefik Ingress가 /api 경로만 api로 넘기므로 헬스체크도 실제 API로 한다 (Redis 캐시로 가벼움)
  health_check {
    path                = "/api/news/home"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# 워커 2대(AZ A·B)만 대상으로 둔다. control plane에는 앱 트래픽을 보내지 않는다
resource "aws_lb_target_group_attachment" "worker" {
  for_each         = { for k, v in aws_instance.node : k => v if k != "cp" }
  target_group_arn = aws_lb_target_group.traefik.arn
  target_id        = each.value.id
  port             = tolist(var.alb_target_ports)[0]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.main.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }
}
