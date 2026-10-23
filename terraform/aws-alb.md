# ALB·HTTPS 적용 (M4-4)

도메인은 외부 업체 DNS를 쓴다. 도메인 이름은 접속 주소라 저장소에 두지 않고 `terraform.tfvars`의 `domain_name`에만 넣는다.

| 주소 | 대상 |
|---|---|
| `api.<domain_name>` | ALB (HTTPS) → 워커 NodePort 30080 → Traefik → api |
| `<domain_name>` | 프론트 CloudFront (M4-12) |

## 1. 인증서만 먼저 만들기

```bash
echo 'domain_name = "<서비스 도메인>"' >> terraform.tfvars
terraform apply -target=aws_acm_certificate.main
terraform output cert_validation_records
```

## 2. 도메인 업체 DNS에 검증 CNAME 등록

출력된 `name` → `value`를 CNAME으로 등록한다 (도메인과 와일드카드가 같은 값이면 1개만).
업체가 이름 끝의 도메인을 자동으로 붙이면 `name`에서 도메인 부분을 빼고 넣는다.

```bash
dig +short CNAME <name>     # value가 나오면 등록 완료
```

## 3. 전체 적용

```bash
terraform plan -out=tfplan && terraform apply tfplan   # 인증서 발급을 기다린 뒤 ALB 생성
terraform output alb_dns_name
```

## 4. api 주소 연결과 확인

도메인 업체 DNS에 `api.<domain_name>` CNAME → `alb_dns_name` 등록.

```bash
curl -sI http://api.<domain_name>/api/news/home | head -3    # 301 → https
curl -s -o /dev/null -w "%{http_code}\n" https://api.<domain_name>/api/news/home   # 200
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names team01-traefik-web --query 'TargetGroups[0].TargetGroupArn' --output text) --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
```

비용: ALB 시간당 약 0.0225달러 + 사용량(LCU). 작업하지 않는 날이 길면 `terraform destroy -target=aws_lb.main` 대신 그대로 두는 편이 재설정 부담이 적다.
