#!/bin/bash

# tokenの有効期限（秒単位）
TOKEN_TTL="3600"

# token生成
TOKEN=$(kubeadm token create --ttl ${TOKEN_TTL} | awk '{print $1}')

# CA証明書のハッシュ値を取得
CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n')

# tokenとCA証明書のハッシュ値の表示
echo "Join this node with the following command:"
echo "kubeadm join <MASTER_IP>:<MASTER_PORT> --token ${TOKEN} \
    --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH}"

# tokenとCA証明書のハッシュ値をファイルに保存する場合
# echo "TOKEN=${TOKEN}" > node-token.txt
# echo "CA_CERT_HASH=${CA_CERT_HASH}" >> node-token.txt
