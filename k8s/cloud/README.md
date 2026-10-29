# AWS 앱 배포 (EKS + Argo CD)

M5-3부터 AWS 운영 클러스터는 EKS(`team01-eks`)이고, 배포는 온프렘과 같은 GitOps 방식이다.

```
백엔드 main 머지 → 백엔드 CI가 이미지 push → deploy-aws 호출 (GitHub 호스팅 러너, 클러스터 접근 없음)
→ deploy/aws 브랜치에 develop을 합치고 태그 커밋 (deploy/tags-aws.yaml)
→ EKS 안의 Argo CD(newsbrief-aws)가 3분 안에 반영
→ workflow가 공개 API로 확인 (X-App-Version 헤더가 있으면 SHA 비교, 없으면 200 확인)
```

| 무엇 | 어디 |
|---|---|
| 앱 차트, values-aws.yaml | develop `charts/newsbrief` (PR) |
| 이미지 태그 | deploy/aws `deploy/tags-aws.yaml` (deploy-aws workflow만 커밋) |
| RDS·Redis 주소, 화면 주소, AI 모드 | EKS의 Argo CD Application `newsbrief-aws` (저장소에 없음, 예시: `argocd/newsbrief-aws.yaml.example`) |
| Secret (DB 비밀번호, JWT, GHCR) | EKS news 네임스페이스 (저장소에 없음) |

- AWS는 운영이라 develop을 deploy/aws에 **자동으로 합치지 않는다.** deploy-aws가 돌 때만 차트 변경이 함께 나간다 (온프렘은 sync-deploy-onprem이 자동으로 합침)
- 롤백: deploy-aws를 이전 SHA로 수동 실행 (또는 deploy/aws의 태그 커밋 되돌리기)

## GitHub Variables

| 이름 | 쓰임 |
|---|---|
| `AWS_APP_ORIGIN` | `https://app.<도메인>`. deploy-aws가 배포 후 확인에 사용 |

`AWS_DB_HOST`, `AWS_REDIS_HOST`, `AWS_AI_MODE`는 kubeadm 시절 값이다. 이제는 Argo CD Application에 있으므로 쓰지 않는다.

## AI 모드 바꾸기 (mock ↔ bedrock)

```bash
kubectl --context team01-eks -n argocd patch application newsbrief-aws --type json \
  -p '[{"op":"replace","path":"/spec/source/helm/parameters/3/value","value":"mock"}]'
# 설정(ConfigMap)만 바뀌므로 파드를 다시 띄워야 반영된다
kubectl --context team01-eks -n news rollout restart deploy/api deploy/worker
```

## EKS를 새로 만들었을 때 (클러스터 재생성·M5-5)

1. `terraform apply` (terraform/aws-eks.md)
2. `aws eks update-kubeconfig --name team01-eks --alias team01-eks`
3. `bash k8s/cloud/eks-setup.sh` : Traefik, Secret, Argo CD, Application, Pod Identity·30080 경로 확인
   - Secret은 기존 kubeadm 클러스터가 있으면 `KUBEADM_CP_ID=<인스턴스 ID>`로 복사, 없으면 `read -s`로 입력
4. ALB 전환: `terraform.tfvars`에 `alb_backend = "eks"` → apply

## 태그 브랜치 만들기 (deploy/aws가 없을 때)

```bash
git checkout develop && git pull && git checkout -b deploy/aws
mkdir -p deploy
cat > deploy/tags-aws.yaml <<'TAGS'
# deploy-aws workflow가 갱신한다. Argo CD(EKS)가 이 파일의 태그로 AWS에 배포한다
backend:
  image:
    tag: "<지금 운영 중인 백엔드 SHA 40자리>"
TAGS
git add deploy/tags-aws.yaml && git commit -m "deploy(aws): 초기 태그" && git push -u origin deploy/aws
git checkout develop
```

## Argo CD 화면 (EKS)

```bash
kubectl --context team01-eks -n argocd port-forward svc/argocd-server 8081:80
# 브라우저 http://localhost:8081 , 처음 비밀번호(cp가 아니라 맥에서만 확인, 채팅에 올리지 않음):
kubectl --context team01-eks -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

로그인 후 비밀번호를 바꾸고 `argocd-initial-admin-secret`을 지운다.

## api 자동 확장 (HPA, M5-10)

`values-aws.yaml`에서 `backend.api.hpa.enabled: true`. 최소 2, 최대 4, 평균 CPU 70%(요청 250m 기준 175m), 줄일 때 2분 대기.
HPA를 켜면 api Deployment에 `replicas`를 쓰지 않는다. 쓰면 Argo CD selfHeal이 Git 값(2)으로 되돌려 HPA와 개수를 두고 다툰다.

```bash
kubectl --context team01-eks -n news get hpa api -w          # TARGETS(현재 CPU/기준)와 REPLICAS 변화
kubectl --context team01-eks -n news describe hpa api | tail -15   # 늘리고 줄인 시각(Events)
```

- 처음 적용할 때 Deployment에서 `replicas`가 빠지면서 잠깐 1개가 됐다가 HPA가 바로 2개로 맞춘다 (사용자 적은 시간에 적용)
- 온프렘은 metrics-server를 확인한 뒤 `values-onprem.yaml`에서 켠다

## 모니터링 (EKS, M5-8)

온프렘과 같은 kube-prometheus-stack(92.10.1)·대시보드·알림 규칙을 쓴다. 설정 차이는 `monitoring-values.yaml`에 있다.

```bash
bash k8s/cloud/monitoring-setup.sh   # 처음 한 번 Grafana 비밀번호를 read -s로 입력
kubectl --context team01-eks -n monitoring port-forward svc/kps-grafana 3000:80
# 브라우저 http://localhost:3000 → 대시보드 'NewsBrief 서비스'
```

| 항목 | 온프렘 | EKS | 이유 |
|---|---|---|---|
| 지표 저장 | local-path 5Gi, 3일 | emptyDir, 1일 | EBS CSI 없음, 밤에 노드 0대라 이어지지 않음 |
| Grafana 접속 | NodePort 30300 | port-forward | 노드는 프라이빗 서브넷, ALB는 앱만 연결 |
| Alertmanager | 켬 | 끔 | 노드당 파드 17개 제한. 알림은 Grafana Alerting 화면에서 확인 |
| 컨트롤 플레인 지표 | etcd 등 끔 | etcd 등 끔 | EKS는 AWS가 관리 |

모니터링은 Argo CD가 아니라 Helm으로 직접 관리한다(온프렘과 같음). 밤에 노드를 0대로 줄였다가 다시 늘리면 지표는 그때부터 새로 쌓인다.

### 클라우드 관리형 자원 (ALB·RDS·Redis)

ALB·RDS·Redis는 클러스터 밖(AWS 관리형)이라 Prometheus가 아니라 CloudWatch 지표로 본다.

```bash
bash k8s/cloud/aws-metrics.sh        # 최근 60분
bash k8s/cloud/aws-metrics.sh 1440   # 최근 하루
```

| 자원 | 지표 | 보는 법 |
|---|---|---|
| ALB | 대상 상태, UnHealthyHostCount | healthy 2개(노드 수)가 정상. unhealthy면 노드 30080 → Traefik 경로 문제 |
| ALB | HTTPCode_ELB_5XX_Count | ALB가 직접 낸 5xx(502·503). 정상 대상이 없을 때 생긴다 → 대상 상태부터 확인 |
| ALB | HTTPCode_Target_5XX_Count | 앱(Traefik 뒤)이 낸 5xx. Grafana 대시보드의 5xx 패널과 같이 본다 |
| ALB | TargetResponseTime p95 | 사용자 기준 응답 시간. 대시보드 p95(Traefik 기준)보다 ALB 구간만큼 조금 크다 |
| RDS | DatabaseConnections | db.t3.micro는 연결 한도가 작다. 파드 수 × 연결 풀(5)보다 크게 늘면 누수 의심 |
| RDS | CPUUtilization, FreeableMemory | 배치(요약) 시각에 잠깐 오르는 것은 정상 |
| Redis | 상태, CurrConnections | available이 정상. 연결 0이면 앱이 캐시에 못 붙는 것 |
| Redis | DatabaseMemoryUsagePercentage, Evictions | 메모리가 차서 Evictions가 생기면 캐시가 밀려나 DB 조회가 늘어난다 |

콘솔에서 볼 때: CloudWatch → 지표 → ApplicationELB(team01-alb), RDS(team01-news-*), ElastiCache(team01-redis-*).
Grafana에 CloudWatch 데이터 소스를 붙이려면 Grafana 파드에 CloudWatch 읽기 권한(Pod Identity)이 필요해 Terraform 변경이 따른다. 지금은 위 스크립트·콘솔로 확인한다.

## 이전 방식 (kubeadm, M4-5 ~ M5-7)

kubeadm control plane의 self-hosted runner(라벨 `aws`)가 Helm으로 배포했다. EKS 전환 후 kubeadm EC2는 되돌리기용으로 중지해 두었고, 정리할 때 runner 등록도 지운다 (infra 저장소 Settings → Actions → Runners → aws-cp).
