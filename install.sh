#/bin/sh

NAMESPACE=$(helm inspect kiam-install/|grep namespace|cut -d: -f2|xargs)
SERVICENAME=$(helm inspect kiam-install/|grep serviceName|cut -d: -f2|xargs)
FQDN=${SERVICENAME}.${NAMESPACE}.svc.cluster.local

JSON=$(cat<<EOF
{
  "CN": "Kiam Server",
  "hosts": [
      "127.0.0.1",
      "127.0.0.1:443",
      "127.0.0.1:9610",
      "localhost",
      "localhost:443",
      "localhost:9610",
      "${FQDN}",
      "${FQDN}:443"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
        "C":  "USA",
        "L":  "Little Rock",
        "O":  "Angel Eye Camera Systems",
        "OU": "WWW",
        "ST": "AR"
    }
  ]
}
EOF
)

echo "$JSON" >server.json

cfssl gencert -initca ca.json | cfssljson -bare ca
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=default server.json | cfssljson -bare server
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=default agent.json | cfssljson -bare agent

kubectl --kubeconfig ~/.kube/config delete secret kiam-server-tls $NAMESPACE >/dev/null 2>&1
kubectl --kubeconfig ~/.kube/config delete secret kiam-agent-tls $NAMESPACE >/dev/null 2>&1

kubectl --kubeconfig ~/.kube/config create secret generic $NAMESPACE kiam-server-tls  \
  --from-file=ca.pem \
  --from-file=server.pem \
  --from-file=server-key.pem

kubectl --kubeconfig ~/.kube/config create secret generic $NAMESPACE kiam-agent-tls  \
  --from-file=ca.pem \
  --from-file=agent.pem \
  --from-file=agent-key.pem

helm del --purge ${1}
helm install -f ${1}/values.yaml ./${1}/ --name ${2}

rm -f *.pem
