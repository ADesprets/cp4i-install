#!/bin/bash

# name: Generate apic installation file
# requirement :
#         update apic.properties

echo "Install APIC -- Start: `date`"
SECONDS=0

check_file () {
	if [ -f "$1" ]; then
    		echo "$1 exist --> OK"
	else
    		echo "$1 does not exist  -> KO"
    		exit 1
	fi
}

. ../config/apic.properties

# Check if connexion to cluster is ok
gi=$(kubectl get nodes)
if [ $? -ne 0 ]; then
  exit 1
fi

chmod +x ./*.sh

echo "DOES NOT Generate all yaml files"
./apic.generate-files.util.sh

echo "Check file existing"
check_file ../generated/ibm-apiconnect-crds.yaml
check_file ../generated/ibm-apiconnect.yaml
check_file ../generated/ibm-datapower.yaml
check_file ../generated/management_cr.yaml
check_file ../generated/analytics_cr.yaml
check_file ../generated/portal_cr.yaml
check_file ../generated/apigateway_cr.yaml
check_file ../generated/custom-certs-external.yaml
check_file ../generated/$ADMIN_USER_SECRET.yaml

ns_apic=$(kubectl get namespaces | grep -E -o "\b$NAMESPACE\b")
if [[ -z $ns_apic ]]; then
  echo "--- Create $NAMESPACE namespace"
  kubectl create namespace $NAMESPACE
else
  echo "$NAMESPACE namespace already exists"
fi

echo "--- Create secret for Entitlement Registry"
kubectl create secret -n $NAMESPACE docker-registry $SECRET_NAME --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_REGISTRY_KEY

echo "--- Deploy custom-certs-external.yaml"
kubectl create -f ../generated/custom-certs-external.yaml -n $NAMESPACE
echo "--- Deploy ibm-apiconnect-crds.yaml"
kubectl create -f ../generated/ibm-apiconnect-crds.yaml -n $NAMESPACE

echo "--- Deploy ibm-apiconnect.yaml"
kubectl create -f ../generated/ibm-apiconnect.yaml -n $NAMESPACE
echo "--- Deploy ibm-datapower.yaml"
kubectl create -f ../generated/ibm-datapower.yaml -n $NAMESPACE

# Temporary fix for cluster role 
echo "--- Temporary fix for cluster-role ibm-apiconnect"
kubectl get ClusterRole ibm-apiconnect -n $NAMESPACE -o yaml > ../generated/cluster_role.yaml
cat ../templates/rbac-fix.yaml >> ../generated/cluster_role.yaml
kubectl apply -f ../generated/cluster_role.yaml -n $NAMESPACE

for step in {1..3}
do
kubectl get po -n $NAMESPACE
bash ./sleep.util.sh 10
done
kubectl get po -n $NAMESPACE
echo "----------------------"

read -n 1 -p "Continue ? [y,n]" doit 
case $doit in  
  y|Y) echo "... Deploy Subsystem" ;; 
  n|N) exit ;; 
  *) exit ;; 
esac

echo "----------------------"
echo "-- Deploy Subsystem --"
echo "----------------------"
echo "--- Deploy Subsystem management_cr.yaml"
kubectl create -f ../generated/management_cr.yaml -n $NAMESPACE
echo "--- Deploy Subsystem analytics_cr.yaml"
kubectl create -f ../generated/analytics_cr.yaml -n $NAMESPACE
echo "--- Deploy Subsystem portal_cr.yaml"
kubectl create -f ../generated/portal_cr.yaml -n $NAMESPACE
echo "--- Deploy Subsystem apigateway_cr.yaml"
kubectl create -f ../generated/$ADMIN_USER_SECRET.yaml -n $NAMESPACE
kubectl create -f ../generated/apigateway_cr.yaml -n $NAMESPACE

echo "The next command will monitor the creation of the containers, you need to type Ctrl + c to stop this action and finish this script"

kubectl get po -n $NAMESPACE -w

echo "----------------------"
kubectl get po -n $NAMESPACE
echo "Install APIC -- End: `date`"

kubectl get ingress -n $NAMESPACE

echo "--------------- Endpoint ---------------------"
echo " Cloud manager : https://$MGMT_ADMIN_EP.$STACK_HOST"
echo " API manager : https://$MGMT_API_EP.$STACK_HOST"
echo "----------------------------------------------"

duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

