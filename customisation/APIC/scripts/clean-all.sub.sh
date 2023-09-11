echo "Delete all APIC resources"

if [ -z "$1" ]
  then
    echo "No argument supplied: clean-all.sh <namespace>"
    echo ""
    echo "To confirm delete resources: clean-all.sh <namespace> DELETE"
    exit
fi

NAMESPACE=$1
CONFIRM=$2

echo "namespace: $NAMESPACE"

if [ ${CONFIRM} = 'DELETE' ]; then

    # Set context
    kubectl config set "contexts."`kubectl config current-context`".namespace" $NAMESPACE

    kubectl delete -f ../generated/apigateway_cr.yaml -n $NAMESPACE
    kubectl delete secret datapower-admin-credentials -n $NAMESPACE
    kubectl delete -f ../generated/portal_cr.yaml -n $NAMESPACE
    kubectl delete -f ../generated/analytics_cr.yaml -n $NAMESPACE
    kubectl delete -f ../generated/management_cr.yaml -n $NAMESPACE
    kubectl delete -f ../generated/custom-certs-external.yaml -n $NAMESPACE
    kubectl delete -f ../generated/ibm-datapower.yaml -n $NAMESPACE
    kubectl delete -f ../generated/ibm-apiconnect.yaml -n $NAMESPACE
    kubectl delete -f ../generated/ibm-apiconnect-crds.yaml -n $NAMESPACE

    PVC=`kubectl get pvc -n $NAMESPACE | awk '{print $1}'`
    PV=`kubectl get pv -n $NAMESPACE |grep $NAMESPACE/ | awk '{print $1}'`
    SECRET=`kubectl get secret -n $NAMESPACE | awk '{print $1}'`
    SVC=`kubectl get svc -n $NAMESPACE| awk '{print $1}'`

    kubectl delete pvc $PVC -n $NAMESPACE
    kubectl delete secret $SECRET -n $NAMESPACE
    kubectl delete pv $PV -n $NAMESPACE
    kubectl delete svc $SVC -n $NAMESPACE

    kubectl get all -n $NAMESPACE
    kubectl delete ns $NAMESPACE
else
	echo "No Delete ..."
fi
