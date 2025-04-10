#!/usr/bin/env bash
# SB]20240506: This script is used to get the certificates from the k8s cluster 
# https://blog.kubovy.eu/2020/05/16/retrieve-tls-certificates-from-kubernetes/

KUBECTL="kubectl"
OUTPUT=${1:-"$(pwd)/certificates"}
NAME=cs-ca-certificate-secret
NAMESPACE=ibm-common-services

if [ -n "$(${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.crt"' | base64 -d)" ]; then
  DOMAIN=$(${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.crt"' | base64 -d | openssl x509 -noout -text | grep "Subject: CN = " | sed -E 's/\s+Subject: CN = ([^ ]*)/\1/g')
  echo -n " ${DOMAIN}"
  mkdir -p "${OUTPUT}/${DOMAIN}"
  ${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.key"' | base64 -d > "${OUTPUT}/${DOMAIN}/privkey.pem"
  ${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.crt"' | base64 -d > "${OUTPUT}/${DOMAIN}/fullchain.pem"
  echo " DONE"
else
  echo " FAILED"
fi
