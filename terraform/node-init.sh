#!/bin/bash
# EC2 노드 공통 준비 (cloud-init, 최초 부팅 1회). 온프렘 VM 준비 과정과 같다.
# kubeadm init/join은 여기서 하지 않는다 (aws-cluster.md).
set -euxo pipefail
exec > /var/log/node-init.log 2>&1

hostnamectl set-hostname ${hostname}

# 1. 스왑 끄기, 커널 모듈·네트워크 설정
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
cat <<MOD > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MOD
modprobe overlay
modprobe br_netfilter
cat <<SYS > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYS
sysctl --system

# 2. containerd (systemd cgroup)
apt-get update
apt-get install -y containerd apt-transport-https ca-certificates curl gpg
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# 3. kubelet·kubeadm·kubectl (온프렘과 같은 버전으로 고정)
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${k8s_minor}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${k8s_minor}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
# awk에서 exit로 일찍 끝내면 apt-cache가 SIGPIPE로 실패하고 pipefail 때문에 스크립트가 멈춘다 → 끝까지 읽고 첫 값만 출력
VER=$(apt-cache madison kubeadm | awk '$3 ~ /^${k8s_version}-/ && !f {print $3; f=1}')
apt-get install -y kubelet="$VER" kubeadm="$VER" kubectl="$VER"
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

touch /var/log/node-init.done
