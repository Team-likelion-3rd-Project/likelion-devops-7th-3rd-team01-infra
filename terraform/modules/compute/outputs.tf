output "nodes" {
  value = { for k, v in aws_instance.node : k => { id = v.id, private_ip = v.private_ip } }
}

output "cert_validation_records" {
  description = "도메인 업체 DNS에 등록할 인증서 검증 CNAME"
  value       = { for o in aws_acm_certificate.main.domain_validation_options : o.domain_name => { name = o.resource_record_name, value = o.resource_record_value } }
}

output "alb_dns_name" {
  description = "api.<domain_name> CNAME 대상"
  value       = aws_lb.main.dns_name
}