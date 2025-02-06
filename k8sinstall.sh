#!/bin/bash
set -e

# -----------------------------------------------------------
# このスクリプトはroot権限で実行してください
# -----------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "このスクリプトはroot権限で実行してください。例: sudo $0"
  exit 1
fi

echo "===== Kubernetes/Containerd インストールと設定開始 ====="

# -----------------------------------------------------------
# 必要なパッケージのインストール
# -----------------------------------------------------------
echo ">> aptパッケージリストの更新と必要パッケージのインストール"
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# -----------------------------------------------------------
# Kubernetesリポジトリの設定と kubeadm/kubelet/kubectl のインストール
# -----------------------------------------------------------
echo ">> Kubernetes リポジトリの登録とパッケージインストール"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# -----------------------------------------------------------
# containerd のインストール（Dockerの公式リポジトリ経由）
# -----------------------------------------------------------
echo ">> Docker公式リポジトリから containerd のインストール"
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y containerd.io

# -----------------------------------------------------------
# containerd の初期設定（SystemdCgroup の設定変更）
# -----------------------------------------------------------
echo ">> containerd の初期設定"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
if grep -q "SystemdCgroup = true" "/etc/containerd/config.toml"; then
  echo "containerd の設定済み（SystemdCgroup = true）: スキップ"
else
  sed -i -e "s/SystemdCgroup \= false/SystemdCgroup \= true/g" /etc/containerd/config.toml
fi
systemctl restart containerd

# -----------------------------------------------------------
# swap の無効化（Kubernetesでは必須）
# -----------------------------------------------------------
echo ">> Swapの無効化"
swapoff -a
# fstab からswapエントリを削除（またはコメントアウト）して恒久的に無効化
sed -i '/swap/d' /etc/fstab

# -----------------------------------------------------------
# カーネルモジュールと sysctl の設定
# -----------------------------------------------------------
echo ">> カーネルモジュールと sysctl の設定"
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# モジュールの即時読み込み
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory                = 1
vm.panic_on_oom                     = 0
kernel.panic                        = 10
kernel.panic_on_oops                = 1
kernel.keys.root_maxkeys            = 1000000
kernel.keys.root_maxbytes           = 25000000
EOF

# 設定の反映
sysctl --system

# -----------------------------------------------------------
# kubeadm 初期化用コンフィグファイルの生成
# -----------------------------------------------------------
echo ">> kubeadm 用初期化設定ファイルの生成"
# ※実行ユーザーのHOMEが /root の場合もあるので注意
KUBE_DIR="${SUDO_USER:+/home/$SUDO_USER}/.kube"
mkdir -p "$KUBE_DIR"

cat <<EOF | tee "$KUBE_DIR/init_config.yaml"
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- token: "$(openssl rand -hex 3).$(openssl rand -hex 8)"
  description: "kubeadm bootstrap token"
  ttl: "24h"
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0" # Prometheus Operator 等で使用する場合
scheduler:
  extraArgs:
    bind-address: "0.0.0.0" # Prometheus Operator 等で使用する場合
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
protectKernelDefaults: true
EOF

echo "===== インストールと設定が完了しました ====="
echo "※ 次のステップとして、生成された $KUBE_DIR/init_config.yaml を元に 'kubeadm init --config \$HOME/.kube/init_config.yaml' を実行してください。"
