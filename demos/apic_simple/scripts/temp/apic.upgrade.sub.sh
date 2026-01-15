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

. ../resources/apic.properties

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


chmod +x ./*.sh

echo "-- check file existing"
check_file ${APICONNECT_RELEASE_FILES}/ibm-apiconnect-crds.yaml
check_file ${APICONNECT_RELEASE_FILES}/ibm-apiconnect.yaml
check_file ${APICONNECT_RELEASE_FILES}/ibm-datapower.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/management_cr.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/analytics_cr.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/portal_cr.yaml
check_file ${APICONNECT_RELEASE_FILES}/helper_files/apigateway_cr.yaml

echo "-- Generate all yaml files"
./generate-apic-files.sh

echo "-- Deploy ibm-apiconnect-crds.yaml"
kubectl apply -f ../generated/ibm-apiconnect-crds.yaml -n $NAMESPACE
echo "-- Deploy ibm-apiconnect.yaml"
kubectl apply -f ../generated/ibm-apiconnect.yaml -n $NAMESPACE
echo "-- Deploy ibm-datapower.yaml"
kubectl apply -f ../generated/ibm-datapower.yaml -n $NAMESPACE
#echo "-- Deploy ingress-issuer-v1-alpha1.yaml"
#kubectl create -f ../templates/ingress-issuer-v1-alpha1.yaml -n $NAMESPACE

for step in {1..4}
do
kubectl get po -n $NAMESPACE
bash ./sleep.util.sh 10
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
kubectl apply -f ../generated/management_cr.yaml -n $NAMESPACE
echo "-- Deploy Subsystem analytics_cr.yaml"
kubectl apply -f ../generated/analytics_cr.yaml -n $NAMESPACE
echo "-- Deploy Subsystem portal_cr.yaml"
kubectl apply -f ../generated/portal_cr.yaml -n $NAMESPACE
echo "-- Deploy Subsystem apigateway_cr.yaml"
#kubectl create -f ../generated/$ADMIN_USER_SECRET.yaml -n $NAMESPACE
kubectl apply -f ../generated/apigateway_cr.yaml -n $NAMESPACE

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

