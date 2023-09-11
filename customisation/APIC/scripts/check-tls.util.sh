echo "Check all certificates"

if [ -z "$1" ]
  then
    echo "No argument supplied: check-tls.sh <namespace>"
    echo ""
    exit
fi

# for macos
OPENSSL=/usr/local/opt/openssl/bin/openssl

# for linux
#OPENSSL=/usr/bin/openssl

# for cert-manager <= 0.10
CERTMANAGER=" certmanager.k8s.io/issuer-name"
# for cert-manager > 0.10
#CERTMANAGER="[[:space:]]cert-manager.io/issuer-name:"

NAMESPACE=$1

# Set context
kubectl config set "contexts."`kubectl config current-context`".namespace" $NAMESPACE

for value in $(kubectl get secret | grep kubernetes.io/tls | awk '{print $1}'); do
 

 secret=$(kubectl get secret $value -o yaml)
 result=$( echo "$secret" | grep " ca.crt" | awk '{ print $2 }' | base64 --decode)
 resulttls=$( echo "$secret" | grep " tls.crt" | awk '{ print $2 }' | base64 --decode)
 resultissuer=$( echo "$secret" | grep $CERTMANAGER | awk '{ print $2 }' )

 if [ -z "$result" ] ; then
        echo "$value = $result  (empty)"
 else
        caenddate=$(echo "$result" | $OPENSSL x509 -enddate -noout -in -)
        tlsenddate=$(echo "$resulttls" | $OPENSSL x509 -enddate -noout -in -)
        echo "$value = ca: $resultissuer enddate: $caenddate tls-end-date: $tlsenddate"
 fi

done
