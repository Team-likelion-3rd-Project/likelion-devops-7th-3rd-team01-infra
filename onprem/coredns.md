# CoreDNS 외부 DNS 설정 (온프렘)

## 바꾼 내용

CoreDNS의 외부 이름 조회 대상을 VM의 `/etc/resolv.conf`에서 공용 DNS로 바꿨다.

```
forward . /etc/resolv.conf      # 변경 전
forward . 1.1.1.1 8.8.8.8       # 변경 후
```

## 이유

VM의 `/etc/resolv.conf`에는 VirtualBox NAT의 IPv6 DNS 주소가 함께 들어 있는데, 이 주소가 응답하지 않을 때가 있었다.
CoreDNS가 그 주소로 물어보면 시간 초과가 나서 배치(RSS 수집)가 가끔 외부 기사 주소를 찾지 못하고 실패했다.

## 적용·확인

```bash
kubectl -n kube-system get cm coredns -o yaml > ~/coredns-backup.yaml   # 백업
kubectl -n kube-system edit cm coredns                                   # forward 줄 수정
kubectl -n kube-system rollout restart deployment coredns
kubectl run dnstest --rm -it --image=busybox:1.36.1 --restart=Never -- nslookup www.etnews.com
```

## 주의

- `kubeadm upgrade` 때 CoreDNS 설정이 기본값으로 돌아갈 수 있다. 업그레이드 후 forward 줄을 다시 확인한다.
- 되돌릴 때: `kubectl apply -f ~/coredns-backup.yaml` 후 rollout restart.
