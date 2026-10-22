# AWS EC2 kubeadm 클러스터 (M4-2)

`terraform apply`로 노드 3대(cp, worker-a, worker-b)가 앱 서브넷에 생긴다. 공인 IP와 SSH 포트가 없으므로 접속은 SSM으로만 한다.
노드 준비(containerd, kubelet·kubeadm·kubectl 1.35.9)는 `node-init.sh`가 첫 부팅 때 자동으로 한다. kubeadm init/join은 아래 순서로 직접 실행한다.

## 0. 준비 (맥)

```bash
brew install --cask session-manager-plugin   # aws ssm start-session 에 필요
export AWS_PROFILE=team01-mfa                 # MFA 임시 자격 증명
cd terraform && terraform output nodes
```

노드 준비 완료 확인 (세 노드 모두 `done`):

```bash
for id in $(terraform output -json nodes | python3 -c 'import json,sys;print(" ".join(v["id"] for v in json.load(sys.stdin).values()))'); do
  c=$(aws ssm send-command --instance-ids $id --document-name AWS-RunShellScript \
      --parameters 'commands=["test -f /var/log/node-init.done && echo done || tail -3 /var/log/node-init.log"]' --query Command.CommandId --output text)
  sleep 4; echo "$id: $(aws ssm get-command-invocation --command-id $c --instance-id $id --query StandardOutputContent --output text)"
done
```

## 1. control plane 초기화

```bash
aws ssm start-session --target <cp 인스턴스 ID>
sudo -i
kubeadm init --kubernetes-version v1.35.9 --pod-network-cidr 10.244.0.0/16
mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
```

## 2. Calico (VXLAN)

워커 두 대가 서로 다른 AZ·서브넷에 있어서 파드 패킷을 감싸서 보내야 한다(VXLAN). 감싸지 않으면 AWS가 출발지가 맞지 않는 패킷을 버린다. 온프렘과 같은 Calico 버전을 쓰고, IP 풀만 VXLAN으로 둔다 (`encapsulation: VXLAN`, 파드 대역 10.244.0.0/16).

## 3. 워커 참여

cp에서 `kubeadm token create --print-join-command` 출력을 복사해, 각 워커에 `aws ssm start-session`으로 들어가 `sudo` 로 실행한다. join 명령(토큰)은 채팅·문서에 남기지 않는다.

## 4. 확인

```bash
kubectl get nodes -o wide          # 3대 Ready
kubectl run t1 --image=busybox:1.36.1 --overrides='{"spec":{"nodeName":"aws-worker-a"}}' -- sleep 600
kubectl run t2 --image=busybox:1.36.1 --overrides='{"spec":{"nodeName":"aws-worker-b"}}' -- sleep 600
kubectl exec t1 -- ping -c 3 $(kubectl get pod t2 -o jsonpath='{.status.podIP}')   # 다른 AZ 파드 간 통신
kubectl delete pod t1 t2
```

## 비용 (서울, 온디맨드)

| 구성 | 시간당 | 하루 24시간 |
|---|---|---|
| NAT 1개 + EIP (`nat_mode=single`, 기본) | 약 0.064달러 | 약 1.5달러 |
| EC2 3대 t3.medium | 약 0.156달러 | 약 3.7달러 |
| 합계 | 약 0.22달러 | 약 5.3달러 |

작업하지 않을 때는 멈춘다. EC2는 중지하면 디스크 비용만 남고, NAT는 지워야 과금이 멈춘다.

```bash
# 멈추기 (저녁)
IDS=$(terraform output -json nodes | python3 -c 'import json,sys;print(" ".join(v["id"] for v in json.load(sys.stdin).values()))')
aws ec2 stop-instances --instance-ids $IDS
terraform apply -var nat_mode=none          # NAT·EIP 삭제

# 다시 켜기 (아침)
terraform apply                             # NAT 1개 다시 생성 (기본 single)
aws ec2 start-instances --instance-ids $IDS
```

EC2를 중지했다 켜도 사설 IP가 그대로라 클러스터는 그대로 돌아온다. NAT를 다시 만들면 나가는 공인 IP가 바뀐다(외부에 등록한 IP가 없어 영향 없음).
장애 시나리오 C2(한쪽 AZ 중지)를 시험할 때만 `-var nat_mode=per_az`로 AZ마다 NAT를 둔다.
