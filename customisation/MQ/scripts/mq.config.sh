#!/bin/bash
#####################################################################################################################
# Prepare TLS repository, key, cert
# Think about using redirection : 2>&1 > Out-Null
# https://community.ibm.com/community/user/integration/blogs/atul-sharma/2022/01/06/ibm-mq-in-kubernetes-enabling-tls
# Site qui explique comment utiliser des CA dans TLS MQ
#####################################################################################################################

########################################################
# Get the CA (cs-ca-issuer) tls resources (ca, cert key)
########################################################
function get_issuer_tls_resources () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :get_issuer_tls_resources"

  local lf_ca_crt="${sc_ca_crtdir}ca-crt.pem"

  # SB]20240506: based on the script found here: 
  # https://blog.kubovy.eu/2020/05/16/retrieve-tls-certificates-from-kubernetes/

  KUBECTL="kubectl"
  NAME=cs-ca-certificate-secret
  NAMESPACE=ibm-common-services

  if [ -n "$(${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.crt"' | base64 -d)" ]; then
    check_directory_exist_create "${sc_ca_crtdir}"
    ${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.key"' | base64 -d > "${sc_ca_crtdir}ca-key.pem"
    ${KUBECTL} get secret -n ${NAMESPACE} ${NAME} -o json | jq -r '.data."tls.crt"' | base64 -d > "${sc_ca_crtdir}ca-crt.pem"
  else
    mylog error " secret $NAME not found in namespace $NAMESPACE"
    exit 1
  fi  

  decho "F:OUT:get_issuer_tls_resources"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

#####################################################
# Prepare CA signed certificates for qmgr
#####################################################
function create_qmgr_ca_tls () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_qmgr_ca_tls"

  local lf_crt_file="${sc_srv_crtdir}qmgr-crt.pem"
  local lf_csr_file="${sc_srv_crtdir}qmgr-req.pem"
  local lf_key_file="${sc_srv_crtdir}qmgr-key.pem"
  local lf_subject=${SUBJECT_SRV}
  
  # Generate the CSR for the enity (qmgr|client)
  openssl req -new -newkey rsa:${KEY_SIZE} -nodes -passout file:${PASSPHRASE_FILE} -subj "${lf_subject}" -keyout ${lf_key_file} -out ${lf_csr_file}

  # Generate the entity (qmgr|client) certificate signed by the CA
  openssl x509 -req -days ${VALIDITY_DAYS} -passin file:${PASSPHRASE_FILE} -in ${lf_csr_file} -out ${lf_crt_file} -CA "${sc_ca_crtdir}ca-crt.pem" -CAkey "${sc_ca_crtdir}ca-key.pem"

  decho "F:OUT:create_qmgr_ca_tls"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

#################################################
# Create client key repository
#################################################
function create_clnt_kdb () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_clnt_kdb"

  mylog "info" "Creating   : client key database for $sc_clnt to use with MQSSLKEYR env variable."

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $KEYDB_TYPE -stash > /dev/null 2>&1  

  decho "F:OUT:create_clnt_kdb"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Add qmgr certs to client keydb
#################################################
function add_qmgr_crt_2_clnt_kdb () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :add_qmgr_crt_2_clnt_kdb"

  mylog "info" "Adding     : qmgr certificate to the client key database"

  local lf_srv_crt="${sc_srv_crtdir}qmgr-crt.pem"

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  

  #decho "lf_clnt_keydb=$lf_clnt_keydb|lf_srv_crt=$lf_srv_crt"

  # Add the queue manager public key to the client key database
	runmqakm -cert -add -db $lf_clnt_keydb -label $QMGR -file $lf_srv_crt -format ascii -stashed > /dev/null 2>&1

  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1

  decho "F:OUT:add_qmgr_crt_2_clnt_kdb"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

###############################################################################################################################
# Add CA crt to client keydb
# MQ Explorer is a Java application. 
# Java applications use a different type of key store, called JKS. 
# In JKS, there are two stores:
#   - Trust store: this will contain the queue manager's signer (CA) certificate. 
#                  In the case of self-signed certificates, the trust store will contain the queue manager's certificate itself.
#   - Key store: this will contain the client's (that is, MQ Explorer's) certificate and private key.
###############################################################################################################################
function add_ca_crt_2_clnt_kdb () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :add_ca_crt_2_clnt_kdb"

  local lf_ca_crt="${sc_ca_crtdir}ca-crt.pem"

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  
                                        
  # In order for the cert validation chain to work, we also import the CA cert. 
  # The client program will therefore be able to validate the cert send from the qmgr that is signed by this CA.
  # check first if the ca certificate is already in keystore
  runmqakm -cert -details -label "ca" -db $lf_clnt_keydb -stashed > /dev/null 2>&1 
  if [ $? -ne 0 ]; then
    runmqakm -cert -add -db $lf_clnt_keydb -label "CN=cs-ca-certificate" -file $lf_ca_crt -format ascii -stashed > /dev/null 2>&1  
  fi
                    
  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1  

  decho "F:OUT:add_ca_crt_2_clnt_kdb"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

#####################################################
# Create pki infrastructure : keys, certs, kdb, ....
#####################################################
function create_pki_cr () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_pki_cr"

  ##-- Get the private/cert/ca for the Issuer cs-ca-issuer 
  mylog "info" "Getting   : certificate and key for CA"
  get_issuer_tls_resources
  
  ##-- Create a private key and a ca signed certificate for the queue manager
  mylog "info" "Creating   : certificate and key for qmgr $QMGR"
  create_qmgr_ca_tls

  ##-- Create the client key database 
  mylog "info" "Creating   : client key database for $sc_clnt to use with MQSSLKEYR env variable."
  create_clnt_kdb
  
  ##-- Add the queue manager's certificate to the client key database:
  mylog "info" "Adding     : qmgr certificate to the client key database"
  add_qmgr_crt_2_clnt_kdb
  
  ##-- Add CA crt to client kdb
  mylog "info" "Adding     : ca certificate to client kdb for $sc_clnt"
  add_ca_crt_2_clnt_kdb

  decho "F:OUT:create_pki_cr"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create Openshift qmgr
#################################################
function create_oc_qmgr () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_oc_qmgr"
  
  local lf_tmpl_file="${TMPLYAMLDIR}qmgr_tmpl.yaml"
  local lf_gen_file="${sc_generatedyamldir}qmgr.yaml"
  local lf_srv_crt="${sc_srv_crtdir}qmgr-crt.pem"
  local lf_srv_key="${sc_srv_crtdir}qmgr-key.pem"
  local lf_ca_crt="${sc_ca_crtdir}ca-crt.pem"	

  export B64_CA_CRT=$(encode_b64_file $lf_ca_crt)  
  export B64_QMGR_CRT=$(encode_b64_file $lf_srv_crt)
  export B64_QMGR_KEY=$(encode_b64_file $lf_srv_key)

  cat  ${lf_tmpl_file} | envsubst > ${lf_gen_file}
 
  ##-- Creating MQ instances
  mylog "info" "Creating   : ${QMGR}/QueueManager"

  # Apply
  oc apply -f $lf_gen_file 
  lf_octype="QueueManager"
  lf_ocstate="Running"
  lf_ocpath=".status.phase"
  lf_msg="$lf_octype $QMGR $lf_ocpath is $lf_ocstate"
  lf_command="oc get ${lf_octype} ${QMGR} -n ${MY_OC_PROJECT} --output json|jq -r ${lf_ocpath}"
  
  decho "lf_octype=$lf_octype|lf_ocstate=$lf_ocstate|lf_ocpath=$lf_ocpath|lf_msg=$lf_msg|lf_command=$lf_command"
  
  wait_for_state "${lf_msg}" "${lf_ocstate}" "${lf_command}"

  decho "F:OUT:create_oc_qmgr"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create Openshift CCDT file
################################################
function create_ccdt () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_ccdt"
 
  # check for the existence of all needed files 

  # Generate ccdt file
  mylog "info" "Creating   : ccdt file to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  export ROOTURL=$(oc get route -n $MY_OC_PROJECT "${QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho "ROOTURL=$ROOTURL"

  check_file_exist $sc_ccdt_tmpl_file
  cat ${sc_ccdt_tmpl_file} | envsubst > ${MQCCDTURL}

  decho "F:OUT:create_ccdt"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################################################################
# Start of the script main entry
# main

starting=$(date);

# Creation d'un Queue Manager
SECONDS=0

# end with / on purpose
#SCRIPTDIR=$(dirname "$0")/
SCRIPTDIR="${MQ_SCRIPTDIR}scripts/"
CONFIGDIR="${SCRIPTDIR}../config/"

MAINSCRIPTDIR="${SCRIPTDIR}../../../"

# Template directories
TMPLJSONDIR="${SCRIPTDIR}tmpl/json/"
TMPLYAMLDIR="${SCRIPTDIR}tmpl/yaml/"
TMPLTLSDIR="${SCRIPTDIR}tmpl/tls/"
OPENSSLDIR="${SCRIPTDIR}openssl/"


# SB]20240404 Global Index sequence for incremental output for each function call
SC_SPACES_COUNTER=0
SC_SPACES_INCR=3

# parameters
sc_clnt="clnt1"

# load helper functions
. "${MAINSCRIPTDIR}"lib.sh

# I have to get first the qmgr name because it's used in the following configfile
export QMGR=$(echo "${MY_MQ_INSTANCE_NAME}"| tr '[:upper:]' '[:lower:]')
export QMGR_UC=$(echo $QMGR | tr '[:lower:]' '[:upper:]')
export CLNT1="${sc_clnt}"

# load config file
read_config_file "${CONFIGDIR}mq.properties"

check_directory_exist_create  "${MQ_GEN_CUSTOMDIR}generated/${QMGR}"
sc_generateddir="${MQ_GEN_CUSTOMDIR}generated/${QMGR}/"

check_directory_exist_create  "${sc_generateddir}json"
sc_generatedjsondir="${sc_generateddir}json/"

check_directory_exist_create  "${sc_generateddir}yaml"
sc_generatedyamldir="${sc_generateddir}yaml/"

check_directory_exist_create  "${sc_generateddir}tls/ca"
sc_ca_crtdir="${sc_generateddir}tls/ca/"

check_directory_exist_create  "${sc_generateddir}tls/${sc_clnt}"
sc_clnt_crtdir="${sc_generateddir}tls/${sc_clnt}/"

check_directory_exist_create  "${sc_generateddir}tls/qmgr"
sc_srv_crtdir="${sc_generateddir}tls/qmgr/"

# CCDT tmpl file
sc_ccdt_tmpl_file="${TMPLJSONDIR}ccdt_tmpl.json";
MQCCDTURL="${sc_generatedjsondir}ccdt.json"

: <<'END_COMMENT'
END_COMMENT
# Create PKI resources for qmgr and client
create_pki_cr

# Create openshift resources for qmgr (secrets, cm, qmgr, route, ....)
create_oc_qmgr

# Create CCDT file
create_ccdt

#check_create_oc_yaml "QueueManager" "QM1" "${configdir}QM1.yaml" $mq_project
#check_resource_availability "QueueManager" "${mq_instance_name}-qm1" $mq_project
#wait_for_state QueueManager "${mq_instance_name}-qm1" "Running" '.status.phase' $mq_project

duration=$SECONDS
mylog info "Creation of the Queue Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2