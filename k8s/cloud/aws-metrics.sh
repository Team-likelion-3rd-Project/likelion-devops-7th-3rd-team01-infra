#!/usr/bin/env bash
# 클라우드 관리형 자원(ALB·RDS·Redis) 상태와 최근 지표를 CloudWatch에서 한 번에 본다 (M5-8). 맥에서 실행
#   bash k8s/cloud/aws-metrics.sh [분, 기본 60]
# 필요: MFA 세션(AWS_PROFILE). 조회만 하고, 주소·IP·계정 ID는 출력하지 않는다
# 클러스터 안 지표(요청 수·5xx·p95 등)는 Grafana 'NewsBrief 서비스' 대시보드에서 본다. 이 스크립트는 그 바깥(ALB 자체 오류, DB·캐시)을 본다
set -euo pipefail
export AWS_PAGER=""
MIN="${1:-60}"
if date -v-1M >/dev/null 2>&1; then START="$(date -u -v-"${MIN}"M +%FT%TZ)"; else START="$(date -u -d "-${MIN} min" +%FT%TZ)"; fi
END="$(date -u +%FT%TZ)"
PERIOD=$(( MIN * 60 ))

# 지표 하나를 기간 전체 값 하나로 (값이 없으면 '-')
m() { # 네임스페이스 지표 통계 차원...
  local ns=$1 name=$2 stat=$3; shift 3
  local opt=(--statistics "$stat") q="Datapoints[0].$stat"
  [[ $stat == p* ]] && { opt=(--extended-statistics "$stat"); q="Datapoints[0].ExtendedStatistics.$stat"; }
  local v
  v="$(aws cloudwatch get-metric-statistics --namespace "$ns" --metric-name "$name" --dimensions "$@" \
    --start-time "$START" --end-time "$END" --period "$PERIOD" "${opt[@]}" --query "$q" --output text 2>/dev/null || true)"
  [[ -z $v || $v == None ]] && v="-"
  printf '  %-34s %s\n' "$name ($stat)" "$v"
}

echo "기간: 최근 ${MIN}분"

echo "== ALB (team01-alb → 대상 그룹 team01-eks-web)"
LB_ARN="$(aws elbv2 describe-load-balancers --names team01-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
TG_ARN="$(aws elbv2 describe-target-groups --names team01-eks-web --query 'TargetGroups[0].TargetGroupArn' --output text)"
LB="${LB_ARN#*:loadbalancer/}"; TG="${TG_ARN##*:}"
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text | tr '\t' '\n' | sort | uniq -c | awk '{print "  대상 상태: "$2" "$1"개"}'
m AWS/ApplicationELB RequestCount Sum Name=LoadBalancer,Value="$LB"
m AWS/ApplicationELB HTTPCode_ELB_5XX_Count Sum Name=LoadBalancer,Value="$LB"
m AWS/ApplicationELB HTTPCode_Target_5XX_Count Sum Name=LoadBalancer,Value="$LB"
m AWS/ApplicationELB TargetResponseTime p95 Name=LoadBalancer,Value="$LB"
m AWS/ApplicationELB UnHealthyHostCount Maximum Name=TargetGroup,Value="$TG" Name=LoadBalancer,Value="$LB"

echo "== RDS (team01-news-*)"
DB="$(aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'team01-news-')]|[0].DBInstanceIdentifier" --output text)"
aws rds describe-db-instances --db-instance-identifier "$DB" --query 'DBInstances[0].[DBInstanceClass,DBInstanceStatus]' --output text | awk '{print "  "$1" 상태: "$2}'
m AWS/RDS DatabaseConnections Maximum Name=DBInstanceIdentifier,Value="$DB"
m AWS/RDS CPUUtilization Average Name=DBInstanceIdentifier,Value="$DB"
m AWS/RDS FreeableMemory Minimum Name=DBInstanceIdentifier,Value="$DB"

echo "== Redis (team01-redis)"
aws elasticache describe-replication-groups --replication-group-id team01-redis --query 'ReplicationGroups[0].Status' --output text | awk '{print "  상태: "$1}'
for c in $(aws elasticache describe-replication-groups --replication-group-id team01-redis --query 'ReplicationGroups[0].MemberClusters' --output text); do
  echo "  [$c]"
  m AWS/ElastiCache CurrConnections Maximum Name=CacheClusterId,Value="$c"
  m AWS/ElastiCache EngineCPUUtilization Average Name=CacheClusterId,Value="$c"
  m AWS/ElastiCache DatabaseMemoryUsagePercentage Maximum Name=CacheClusterId,Value="$c"
  m AWS/ElastiCache Evictions Sum Name=CacheClusterId,Value="$c"
done
