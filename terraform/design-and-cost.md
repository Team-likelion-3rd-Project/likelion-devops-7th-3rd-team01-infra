# AWS 네트워크 설계와 월 비용 초안 (#47)

작성: 2026-10-19. 기존 System Architecture의 네트워크·접근 제어와 대조했습니다. 게시 시 이 내용을 기존 해당 섹션에 통합합니다. 실제 구축·팀 리뷰 완료를 뜻하지 않습니다.

## 네트워크

VPC 10.20.0.0/16, AZ 2개. 실제 리전·AZ는 계정 허용 범위 확인 후 확정합니다.

| 계층 | A | B | 기본 경로 |
|---|---|---|---|
| Public | 10.20.0.0/24 | 10.20.1.0/24 | IGW |
| App private | 10.20.10.0/24 | 10.20.11.0/24 | 같은 AZ NAT |
| Data private | 10.20.20.0/24 | 10.20.21.0/24 | 인터넷 기본 경로 없음 |

NAT는 public A/B에 1개씩 총 2개입니다. 모든 표에 local 경로를 유지합니다. 앱·데이터 공인 IPv4 자동 할당을 끕니다. S3·CloudFront는 VPC 서브넷 안에 두지 않습니다.

## 접근 제어

| 출발지 | 목적지 | TCP 포트 | 코드 |
|---|---|---|---|
| 인터넷 | sg-alb | 80/443 | 작성 |
| sg-alb | sg-app | 확정 대상·헬스 포트 | 필수 입력 변수 |
| sg-app | sg-db | 3306 | 작성 |
| sg-app | sg-redis | 6379 | 작성 |
| sg-app | 외부 IPv4 | 443 | 같은 AZ NAT 경유 |

ALB 아웃바운드도 대상·헬스 포트만 허용합니다. DB·Redis는 신규 아웃바운드를 허용하지 않으며 허용된 연결의 응답은 stateful 규칙을 따릅니다. SSH·API 서버 인터넷 전체 공개 규칙은 없습니다.

현재 infra 백엔드는 컨테이너/Service 8080, readiness `/actuator/health/readiness`, liveness `/actuator/health/liveness`를 사용합니다. 온프렘 Traefik NodePort는 HTTP 30080, HTTPS 30443입니다. M4 #54는 ALB→워커 NodePort를 요구하지만 AWS용 Traefik·대상 그룹 헬스 경로는 확정되지 않았습니다. 따라서 8080 또는 30080을 운영 확정값으로 코드에 넣지 않았습니다.

제어 평면·노드·Calico·관리 접근 규칙은 별도 설계가 필요합니다. 앱 SG 표만으로 kubeadm 클러스터 통신이 완성되지 않습니다. 온프렘 CIDR 중복과 외부 RSS의 HTTPS 사용 여부도 적용 전 확인합니다.

## 월 730시간 비교 견적

서울 리전을 계산에만 사용합니다. Linux 온디맨드·할인/크레딧/세금 제외. 사양은 이전 견적과 비교하기 위한 가정이며 계정에서 MySQL 8.4 및 선택 사양의 생성 가능 여부는 미확인입니다.

2026-10-19 AWS 공식 Price List를 다시 읽었습니다. EC2·RDS·Redis·ALB·NAT 단가는 기존 견적과 같았습니다. Redis는 표준 지원 노드 단가이며 연장 지원 항목을 합산하지 않았습니다. NAT는 Regional 상품이 아닌 AZ별 NAT 상품을 사용했습니다.

| 항목 | 수량·단가 | 월 USD |
|---|---|---:|
| EC2 제어 평면 | t3.medium 1 × $0.052 × 730 | 37.96 |
| EC2 워커 | t3.large 2 × $0.104 × 730 | 151.84 |
| EBS gp3 | 30GB × 3대 × $0.0912 | 8.21 |
| RDS MySQL Multi-AZ | db.t3.medium $0.208 × 730 (Primary/Standby 포함) | 151.84 |
| RDS gp3 Multi-AZ | 20GB × $0.262 (이중화 포함 단가) | 5.24 |
| Redis Primary/Replica | cache.t3.small 2 × $0.049 × 730 | 71.54 |
| NAT 2개 | 2 × $0.059 × 730 | 86.14 |
| NAT 처리량 가정 | 합계 20GB × $0.059 | 1.18 |
| ALB + 평균 1 LCU | ($0.0225 + $0.008) × 730 | 22.27 |
| 공인 IPv4 | NAT 2 + ALB 최소 가정 2, $0.005 × 4 × 730 | 14.60 |
| **위 항목 소계** | 반올림 전 합산 | **550.81** |
| **소계 + 20%** | 프로젝트 전체 예산 확정 아님 | **660.98** |

이 표는 M4 EC2 구성을 한 달 계속 유지하는 비교용입니다. EKS 제어 영역, S3·CloudFront, Route 53·도메인, AI, 로그·추가 백업, 인터넷/AZ 간 전송, CPU 크레딧 초과, 추가 IPv4·LCU는 별도입니다. AWS Pricing Calculator 저장 견적 링크는 아직 만들지 않았습니다. 실제 계정과 엔진·사양 선택 후 Calculator에서 보완해야 합니다.

기존 $316.33(여유 포함 $379.60)은 2~6주차 실습시간·데이터 유지기간 가정의 프로젝트 견적입니다. 이 월 소계와 기간·포함 항목이 다르므로 직접 절감액을 비교하지 않습니다.

## 실습 종료 후 비용 관리

| 자원 | 종료 방법 | 남는 비용·주의 |
|---|---|---|
| EC2 | 중지 또는 불필요 인스턴스 종료 | EBS·스냅샷·보유 공인 IP 등 별도 |
| RDS | 지원 구성은 임시 중지 가능 | 스토리지·백업 요금 유지. 연속 7일 후 자동 재시작 |
| Redis | 캐시 보존 정책·최종 백업 확인 후 삭제 | EC2처럼 중지하는 서비스가 아님. 보존 스냅샷 별도 |
| NAT | 삭제 후 사용하지 않는 EIP 해제 | EC2 중지로 NAT·공인 IP 요금이 멈추지 않음 |
| ALB | 재생성 절차 확보 후 삭제 | EC2 중지로 ALB 요금이 멈추지 않음 |
| EKS (M5) | 재생성 가능한 경우 클러스터 삭제 검토 | 노드만 중지해도 제어 영역 비용 발생 |

데이터·상태 파일·백업은 자동 삭제 목록에 넣지 않습니다. 이 문서는 삭제 실행 지시가 아닙니다. 팀 공용 자원과 보존 대상을 확인한 뒤 종료하고 결과를 기록합니다.

## 출처

- [기존 설계](https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01/wiki/System-Architecture)
- [EC2·EBS·NAT 서울 가격](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/ap-northeast-2/index.json)
- [RDS 서울 가격](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/ap-northeast-2/index.json)
- [ElastiCache 서울 가격](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonElastiCache/current/ap-northeast-2/index.json)
- [ALB 서울 가격](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-northeast-2/index.json)
- [공인 IPv4](https://aws.amazon.com/vpc/pricing/)
- [RDS 임시 중지](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)
- [ElastiCache 삭제](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Clusters.Delete-gs.redis.html)

완료를 위해 남은 일: 사용자 게시 승인, 기존 위키 섹션 통합, 팀원 1명 이상 확인 코멘트. 실제 통신 시험과 계정 검증은 후속 구축 작업에서 진행합니다.
