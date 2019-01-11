#/bin/sh

function usage(){
  cat<<EOF

  Install Kiam, generating certs if requested.
    Usage:  $0 [OPTIONS]

  Options:
    -d <dir>   Directory to install chart from
    -c         Generate certs and save them as secrets
    -r <name>  Release name for helm to use
    -u <name>  Uninstall the provided release and exit

EOF
}

while [[ ! -z $1 ]]; do
  case $1 in
    -d|--tag)
      shift
      DIR="$1"
      ;;
    -c|--generate-certs)
      CERTS="true"
      ;;
    -r|--release)
      shift
      RELEASE="$1"
      ;;
    -u|--uninstall)
      shift
      UNINSTALL="$1"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

NAMESPACE=$(helm inspect $DIR 2>/dev/null|grep namespace|cut -d: -f2|xargs)
SERVICENAME=$(helm inspect $DIR 2>/dev/null|grep serviceName|cut -d: -f2|xargs)
AGENT_TLS=$(helm inspect $DIR 2>/dev/null|grep agentTls|cut -d: -f2|xargs)
SERVER_TLS=$(helm inspect $DIR 2>/dev/null|grep serverTls|cut -d: -f2|xargs)
FQDN=${SERVICENAME}.${NAMESPACE}.svc.cluster.local

if [ ! -z $UNINSTALL ]; then
  helm del --purge $UNINSTALL
  #exit
fi

if [ -z $DIR ] || [ -z $RELEASE ]; then
  echo "  -d and -r options are required unless using -u"
  usage
  exit 2
fi

if ! helm lint $DIR >/dev/null 2>&1; then
  echo "  $DIR is not a path to a valid helm chart"
  usage
  exit 2
fi

if [ ! -f ${DIR}/values.yaml ]; then
  echo "  No values.yaml file included in helm chart"
  usage
  exit 2
fi

if [ -z ${NAMESPACE} ]; then
  echo "  Namespace not declared in values.yaml"
  usage
  exit 2
fi

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
        "O":  "Kiam",
        "OU": "WWW",
        "ST": "AR"
    }
  ]
}
EOF
)

if [ ! -z $CERTS ]; then
  echo "$JSON" >server.json

  cfssl gencert -initca ca.json | cfssljson -bare ca
  cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=default server.json | cfssljson -bare server
  cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=default agent.json | cfssljson -bare agent

  kubectl --kubeconfig ~/.kube/config delete secret $AGENT_TLS -n $NAMESPACE >/dev/null 2>&1
  kubectl --kubeconfig ~/.kube/config delete secret $SERVER_TLS -n $NAMESPACE >/dev/null 2>&1

  kubectl --kubeconfig ~/.kube/config create secret generic -n $NAMESPACE $SERVER_TLS  \
    --from-file=ca.pem \
    --from-file=server.pem \
    --from-file=server-key.pem

  kubectl --kubeconfig ~/.kube/config create secret generic -n $NAMESPACE $AGENT_TLS  \
    --from-file=ca.pem \
    --from-file=agent.pem \
    --from-file=agent-key.pem

  rm -f server.json
  rm -f *.pem
  rm -f *.csr
fi

helm install -f ${DIR}/values.yaml ./${DIR}/ --name ${RELEASE}
