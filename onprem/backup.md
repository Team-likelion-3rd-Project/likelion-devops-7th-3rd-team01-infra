# 온프렘 백업 (M4-7)

| 대상 | 방식 | 시각 | 보관 | 위치 |
|---|---|---|---|---|
| etcd (클러스터 설정 전체) | CronJob `kube-system/etcd-backup`, `etcdctl snapshot save` + `etcdutl snapshot status` 검사 | 매일 03:20 | 7일 | k8s-cp `/var/backups/etcd` (root 전용) |
| MySQL (서비스 데이터) | CronJob `news/mysql-backup`, `mysqldump --single-transaction` | 매일 03:10 | 7일 | PVC `news/mysql-backup` |

etcd 스냅샷에는 모든 Secret이 평문으로 들어 있다. 저장소·채팅·캡처에 올리지 않고, 외부(S3 등)로 옮길 때는 암호화한다.

현재 백업은 같은 VM 디스크에 있다. VM이 망가지면 백업도 함께 잃으므로, AWS 계정 준비 후 S3 복사를 추가한다.

## 적용

```bash
cd ~/infra && git pull
kubectl apply -f k8s/onprem/backup/
```

## 바로 한 번 실행해 보기

```bash
kubectl create job -n news mysql-backup-manual --from=cronjob/mysql-backup
kubectl wait -n news --for=condition=complete job/mysql-backup-manual --timeout=5m
kubectl logs -n news job/mysql-backup-manual

kubectl create job -n kube-system etcd-backup-manual --from=cronjob/etcd-backup
kubectl wait -n kube-system --for=condition=complete job/etcd-backup-manual --timeout=5m
kubectl logs -n kube-system job/etcd-backup-manual -c verify
kubectl logs -n kube-system job/etcd-backup-manual -c rotate
sudo ls -l /var/backups/etcd
```

확인이 끝나면 수동 Job은 지운다: `kubectl delete job -n news mysql-backup-manual; kubectl delete job -n kube-system etcd-backup-manual`

## MySQL 복원 시험

운영 DB는 건드리지 않는다. 빈 임시 MySQL에 최신 덤프를 넣고 테이블별 건수를 운영과 비교한다.

```bash
# 1. 임시 MySQL 띄우기
kubectl apply -f k8s/onprem/backup/restore-test/mysql-restore-test.yaml
kubectl wait -n news --for=condition=ready pod/mysql-restore-test --timeout=3m

# 2. 최신 덤프 복원 (걸린 시간 기록)
time kubectl exec -n news mysql-restore-test -- sh -c '
  f=$(ls -t /backup/news-*.sql* | head -1); echo "복원 파일: $f"
  case "$f" in *.gz) gunzip -c "$f" ;; *) cat "$f" ;; esac | mysql -uroot'

# 3. 테이블별 건수 비교 (운영 / 복원)
Q='SELECT table_name FROM information_schema.tables WHERE table_schema="news" ORDER BY 1'
for t in $(kubectl exec -n news mysql-restore-test -- mysql -uroot -N -e "$Q"); do
  a=$(kubectl exec -n news mysql-0 -- sh -c "MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql -uroot -N -e 'SELECT COUNT(*) FROM news.$t'")
  b=$(kubectl exec -n news mysql-restore-test -- mysql -uroot -N -e "SELECT COUNT(*) FROM news.$t")
  echo "$t 운영=$a 복원=$b"
done

# 4. 정리
kubectl delete -f k8s/onprem/backup/restore-test/mysql-restore-test.yaml
```

덤프 이후 배치가 기사를 더 모았으면 운영 건수가 조금 많을 수 있다. 덤프 직후에 비교한다.

## etcd 복원

실제 복원은 클러스터 전체를 되돌리는 작업이라 M6 장애 시나리오 O2에서 VM 스냅샷을 먼저 떠 두고 진행한다. 평소에는 매 백업마다 `etcdutl snapshot status`로 파일이 깨지지 않았는지만 검사한다.

## 주의

- kubeadm 업그레이드로 etcd 버전이 바뀌면 `etcd-backup.yaml`의 이미지 태그도 같이 올린다.
  확인: `kubectl -n kube-system get pod etcd-k8s-cp -o jsonpath='{.spec.containers[0].image}'`
- 백업 PVC(local-path)는 처음 만들어진 노드에 묶인다. 그 노드 디스크가 망가지면 MySQL 백업도 함께 잃는다.
