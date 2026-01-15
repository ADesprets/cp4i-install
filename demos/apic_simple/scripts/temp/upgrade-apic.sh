#!/bin/bash

# Upgrade API Connect on k8s 
# requirement :
#         update apic.properties

echo "Upgrade APIC -- Start: `date`"
SECONDS=0

function check_file () {
	if [ -f "$1" ]; then
    		echo "$1 exist --> OK"
	else
    		echo "$1 does not exist  -> KO"
    		exit 1
	fi
}

. $PWD/apic.properties

echo " -- Existing instance --"
echo " "
kubectl get apic -n $NAMESPACE 
echo " "
echo " -----------------------"

read -n 1 -p "Continue ? [y,n]" doit 
case $doit in  
  y|Y) echo "... Update beginning" ;; 
  n|N) exit ;; 
  *) exit ;; 
esac


chmod +x scripts/*.sh

echo "-- check file existing"
check_file ${APICONNECT_RELEASE_FILES}/ibm-apiconnect-crds.yaml
check_file ${APICONNECT_RELEASE_FILES}/ibm-apiconnect.yaml
check_file ${APICONNECT_RELEASE_FILES}/ibm-datapower.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/management_cr.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/analytics_cr.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/portal_cr.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/apigateway_cr.yaml

echo "-- Generate all yaml files"
scripts/generate-apic-files.sh

echo "-- Deploy ibm-apiconnect-crds.yaml"
kubectl apply -f updated/ibm-apiconnect-crds.yaml -n $NAMESPACE
echo "-- Deploy ibm-apiconnect.yaml"
kubectl apply -f updated/ibm-apiconnect.yaml -n $NAMESPACE
echo "-- Deploy ibm-datapower.yaml"
kubectl apply -f updated/ibm-datapower.yaml -n $NAMESPACE
#echo "-- Deploy ingress-issuer-v1-alpha1.yaml"
#kubectl create -f yaml/ingress-issuer-v1-alpha1.yaml -n $NAMESPACE

for step in {1..4}
do
kubectl get po -n $NAMESPACE
bash scripts/sleep.sh 10
done
kubectl get po -n $NAMESPACE
echo "----------------------"

read -n 1 -p "Continue ? [y,n]" doitagain 
case $doitagain in  
  y|Y) echo "... Deploy Subsystem" ;; 
  n|N) exit ;; 
  *) exit ;; 
esac


echo "----------------------"
echo "-- Deploy Subsystem --"
echo "----------------------"
echo "-- Deploy Subsystem management_cr.yaml"
kubectl apply -f updated/management_cr.yaml -n $NAMESPACE
echo "-- Deploy Subsystem analytics_cr.yaml"
kubectl apply -f updated/analytics_cr.yaml -n $NAMESPACE
echo "-- Deploy Subsystem portal_cr.yaml"
kubectl apply -f updated/portal_cr.yaml -n $NAMESPACE
echo "-- Deploy Subsystem apigateway_cr.yaml"
#kubectl create -f updated/$ADMIN_USER_SECRET.yaml -n $NAMESPACE
kubectl apply -f updated/apigateway_cr.yaml -n $NAMESPACE

#timeout 15m kubectl get po -n $NAMESPACE -w
kubectl get po -n $NAMESPACE -w

echo "----------------------"
kubectl get po -n $NAMESPACE
echo "Install APIC -- End: `date`"

kubectl get ingress -n $NAMESPACE

echo " -- Existing instance --"
echo " "
kubectl get apic -n $NAMESPACE 
echo " "
echo " -----------------------"

echo "--------------- Endpoint ---------------------"
echo " Cloud manager : https://$MGMT_ADMIN_EP.${STACK_HOST}"
echo " Api manager : https://$MGMT_API_EP.${STACK_HOST}"
echo "----------------------------------------------"


duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

