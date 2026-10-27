# AWS 앱 배포

백엔드 main 머지 → 백엔드 CI가 이미지 push 후 `deploy-aws` 호출 → AWS control plane의 runner가 Helm 차트로 배포한다.
차트는 `charts/newsbrief`, AWS 값은 `values-aws.yaml`이다. 온프렘(`deploy-onprem`)과 같은 차트를 쓰고 values 파일만 다르다.
API 서버를 인터넷에 열지 않고 AWS 액세스 키도 쓰지 않는다 (runner가 VPC 안에서 helm·kubectl 실행).

DB·Redis 주소, 화면 주소, AI 모드는 저장소에 두지 않고 GitHub Variables 값을 배포할 때 `--set-string`으로 넘긴다.
`helm-adopt.sh`는 kubectl로 만든 기존 리소스를 Helm으로 넘길 때 한 번 쓴 스크립트다 (M5-7, 완료).

## GitHub Variables (infra 저장소)

Settings → Secrets and variables → Actions → **Variables**

| 이름 | 값 |
|---|---|
| `AWS_DB_HOST` | `terraform output -raw db_endpoint` |
| `AWS_REDIS_HOST` | `terraform output -raw redis_endpoint` |
| `AWS_APP_ORIGIN` | `https://app.<도메인>` |
| `AWS_AI_MODE` | `mock` 또는 `bedrock` (바꾼 뒤 deploy-aws를 현재 SHA로 수동 실행하면 반영) |

## runner 설치 (AWS cp, 최초 1회, root)

```bash
cd /root/infra && git pull -q
kubectl apply -f k8s/onprem/rbac.yaml        # 배포 전용 SA deployer (온프렘과 같은 권한)

useradd -m -s /bin/bash gha-runner
mkdir -p /opt/actions-runner && cd /opt/actions-runner
curl -fsSLo runner.tgz https://github.com/actions/runner/releases/download/v2.337.0/actions-runner-linux-x64-2.337.0.tar.gz
tar xzf runner.tgz && rm runner.tgz && chown -R gha-runner: /opt/actions-runner

# gha-runner kubeconfig (deployer 토큰, news 네임스페이스만)
TOKEN=$(kubectl -n news get secret deployer-token -o jsonpath='{.data.token}' | base64 -d)
install -d -o gha-runner -m 700 /home/gha-runner/.kube
KCFG=/home/gha-runner/.kube/config
kubectl config --kubeconfig=$KCFG set-cluster aws --server=https://$(hostname -I | awk '{print $1}'):6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true
kubectl config --kubeconfig=$KCFG set-credentials deployer --token="$TOKEN"
kubectl config --kubeconfig=$KCFG set-context aws --cluster=aws --user=deployer --namespace=news
kubectl config --kubeconfig=$KCFG use-context aws
chown gha-runner: $KCFG && chmod 600 $KCFG; unset TOKEN
sudo -u gha-runner kubectl auth can-i patch deployment -n news     # yes
sudo -u gha-runner kubectl auth can-i get secret -n news           # no

# 등록 토큰: infra 저장소 → Settings → Actions → Runners → New self-hosted runner (Linux) 화면의 --token 값
read -s -p "runner 등록 토큰: " RT; echo
sudo -u gha-runner ./config.sh --unattended --url https://github.com/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-infra \
  --token "$RT" --name aws-cp --labels aws --work _work; unset RT
./svc.sh install gha-runner && ./svc.sh start && ./svc.sh status | grep Active
```

EC2를 밤에 중지하면 runner도 꺼진다. 그동안 들어온 배포 요청은 대기하다가 EC2를 켜면 처리된다.

## 백엔드 CI에 추가할 단계 (backend 저장소, image job 끝)

```yaml
      - name: AWS 배포 요청 (main만)
        if: github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ secrets.INFRA_DISPATCH_TOKEN }}
        run: |
          gh api repos/Team-likelion-3rd-Project/likelion-devops-7th-3rd-team01-infra/dispatches \
            -f event_type=deploy-aws \
            -f "client_payload[app]=backend" \
            -f "client_payload[sha]=${GITHUB_SHA}"
```

## 확인

Actions → deploy-aws → Run workflow → 현재 백엔드 SHA → 성공 후 요약에 실행 중인 버전이 같은지 확인.
