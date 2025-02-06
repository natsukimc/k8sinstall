#!/bin/bash

# tokenの有効期限（秒単位）
TOKEN_TTL="3600"

# token生成
TOKEN=$(kubeadm token create --ttl ${TOKEN_TTL} | awk '{print $1}')

# tokenの表示
echo "Join this node with the following command:"
echo "kubeadm join <MASTER_IP>:<MASTER_PORT> --token ${TOKEN} \
    --discovery-token-ca-cert-hash sha256:<CA_CERT_HASH> \
    --tls-bootstrap-token"

# tokenをファイルに保存する場合
# echo "${TOKEN}" > node-token.txt
