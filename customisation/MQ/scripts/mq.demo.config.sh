#!/bin/bash
#####################################################################################################################
# Prepare TLS repository, key, cert
# Think about using redirection : 2>&1 > Out-Null
# https://community.ibm.com/community/user/integration/blogs/atul-sharma/2022/01/06/ibm-mq-in-kubernetes-enabling-tls
# Site qui explique comment utiliser des CA dans TLS MQ
#####################################################################################################################

################################################
# Prepare CA config
#################################################
function create_ca_tls () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_ca_tls"

  local lf_openssl_cnf_file="${OPENSSLDIR}openssl.properties"
 
  # check for the existence of all needed files 
  check_file_exist $lf_openssl_cnf_file

  # Certificate Authority : create the CA using openssl
  # Result: Two PEM files are created
  #   - ca-crt.pem : certificate file, which can be publicly distributed. 
  #   - ca-key.pem : the paired private key file, It should be kept securely.
  openssl genrsa -des3 -passout file:${PASSPHRASE_FILE} -out "${sc_qmgr_ca_crtdir}ca-key.pem" ${KEY_SIZE}
  openssl req -new -x509 -days ${VALIDITY_DAYS} -passin file:${PASSPHRASE_FILE} -subj "${SUBJECT}" -key "${sc_qmgr_ca_crtdir}ca-key.pem" -out "${sc_qmgr_ca_crtdir}ca-crt.pem"

  decho 3 "F:OUT:create_ca_tls"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

#####################################################
# Prepare CA signed certificates for qmgr
#####################################################
function create_qmgr_ca_tls () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_qmgr_ca_tls"

  local lf_crt_file="${sc_qmgr_srv_crtdir}qmgr-crt.pem"
  local lf_csr_file="${sc_qmgr_srv_crtdir}qmgr-req.pem"
  local lf_key_file="${sc_qmgr_srv_crtdir}qmgr-key.pem"
  local lf_subject=${SUBJECT_SRV}
  
  # Generate the CSR for the enity (qmgr|client)
  openssl req -new -newkey rsa:${KEY_SIZE} -nodes -passout file:${PASSPHRASE_FILE} -subj "${lf_subject}" -keyout ${lf_key_file} -out ${lf_csr_file}

  # Generate the entity (qmgr|client) certificate signed by the CA
  openssl x509 -req -days ${VALIDITY_DAYS} -passin file:${PASSPHRASE_FILE} -in ${lf_csr_file} -out ${lf_crt_file} -CA "${sc_qmgr_ca_crtdir}ca-crt.pem" -CAkey "${sc_qmgr_ca_crtdir}ca-key.pem"

  decho 3 "F:OUT:create_qmgr_ca_tls"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

#################################################
# Create client key repository
#################################################
function create_clnt_kdb () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_clnt_kdb"

  mylog "info" "Creating   : client key database for $sc_clnt to use with MQSSLKEYR env variable."

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $KEYDB_TYPE -stash > /dev/null 2>&1  

  decho 3 "F:OUT:create_clnt_kdb"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Add qmgr certs to client keydb
#################################################
function add_qmgr_crt_2_clnt_kdb () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:add_qmgr_crt_2_clnt_kdb"

  mylog "info" "Adding     : qmgr certificate to the client key database"

  local lf_srv_crt="${sc_qmgr_srv_crtdir}qmgr-crt.pem"

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  

  #decho 3 "lf_clnt_keydb=$lf_clnt_keydb|lf_srv_crt=$lf_srv_crt"

  # Add the queue manager public key to the client key database
	runmqakm -cert -add -db $lf_clnt_keydb -label $QMGR -file $lf_srv_crt -format ascii -stashed > /dev/null 2>&1

  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1

  decho 3 "F:OUT:add_qmgr_crt_2_clnt_kdb"
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
  decho 3 "F:IN:add_ca_crt_2_clnt_kdb"

  local lf_ca_crt="${sc_qmgr_ca_crtdir}ca-crt.pem"

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  
                                        
  # In order for the cert validation chain to work, we also import the CA cert. 
  # The client program will therefore be able to validate the cert send from the qmgr that is signed by this CA.
  # check first if the ca certificate is already in keystore
  runmqakm -cert -details -label "ca" -db $lf_clnt_keydb -stashed > /dev/null 2>&1 
  if [ $? -ne 0 ]; then
    runmqakm -cert -add -db $lf_clnt_keydb -label "CN=ca" -file $lf_ca_crt -format ascii -stashed > /dev/null 2>&1  
  fi
                    
  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1  

  decho 3 "F:OUT:add_ca_crt_2_clnt_kdb"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

#####################################################
# Create pki infrastructure : keys, certs, kdb, ....
#####################################################
function create_pki_cr () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_pki_cr"

  ##-- Get the private/cert/ca for the Issuer cs-ca-issuer 
  #mylog "info" "Getting   : certificate and key for CA"
  #get_issuer_tls_resources

  mylog "info" "Creating   : certificate and key for CA"
  create_ca_tls
  
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

  decho 3 "F:OUT:create_pki_cr"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create Openshift qmgr
#################################################
function create_oc_qmgr () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_oc_qmgr"
  
  local lf_tmpl_file="${TMPLYAMLDIR}qmgr_tmpl-v2.yaml"
  local lf_gen_file="${sc_generatedyamldir}qmgr.yaml"
  local lf_srv_crt="${sc_qmgr_srv_crtdir}qmgr-crt.pem"
  local lf_srv_key="${sc_qmgr_srv_crtdir}qmgr-key.pem"
  local lf_ca_crt="${sc_qmgr_ca_crtdir}ca-crt.pem"	

  export B64_CA_CRT=$(encode_b64_file $lf_ca_crt)  
  export B64_QMGR_CRT=$(encode_b64_file $lf_srv_crt)
  export B64_QMGR_KEY=$(encode_b64_file $lf_srv_key)

  cat  ${lf_tmpl_file} | envsubst > ${lf_gen_file}
 
  ##-- Creating MQ instances
  mylog "info" "Creating   : ${QMGR}/QueueManager"

  # Check if the resource already exists
  if oc get -n ${MY_OC_PROJECT} -f ${lf_gen_file} >/dev/null 2>&1; then
    mylog "info" "Resource already exists"
  else
    # Apply
    oc apply -f $lf_gen_file 
    lf_octype="QueueManager"
    lf_ocstate="Running"
    lf_ocpath=".status.phase"
    lf_msg="$lf_octype $QMGR $lf_ocpath is $lf_ocstate"
    lf_command="oc get ${lf_octype} ${QMGR} -n ${MY_OC_PROJECT} --output json|jq -r ${lf_ocpath}"
    
    decho 3 "lf_octype=$lf_octype|lf_ocstate=$lf_ocstate|lf_ocpath=$lf_ocpath|lf_msg=$lf_msg|lf_command=$lf_command"
    wait_for_state "${lf_msg}" "${lf_ocstate}" "${lf_command}"
  fi

  decho 3 "F:OUT:create_oc_qmgr"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create Openshift CCDT file
################################################
function create_ccdt () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_ccdt"
 
  # check for the existence of all needed files 

  # Generate ccdt file
  mylog "info" "Creating   : ccdt file to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  export ROOTURL=$(oc get route -n $MY_OC_PROJECT "${QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho 3 "ROOTURL=$ROOTURL"

  check_file_exist $sc_ccdt_tmpl_file
  cat ${sc_ccdt_tmpl_file} | envsubst > ${MQCCDTURL}

  decho 3 "F:OUT:create_ccdt"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create helper scripts, put, browse and get messages in a queue
################################################
function create_helper_scripts () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_helper_scripts"
 
  # Generate herlper scripts files
  mylog "info" "Helper scripts in ${sc_generatedshdir} directory"

  export MQ_GEN_CCDT_DIR=${sc_generatedjsondir}
  export MQ_GEN_KDB=${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.kdb

  adapt_file ${MQ_TMPLSHDIR} ${sc_generatedshdir} run-qm-client-put.sh
  adapt_file ${MQ_TMPLSHDIR} ${sc_generatedshdir} run-qm-client-browse.sh
  adapt_file ${MQ_TMPLSHDIR} ${sc_generatedshdir} run-qm-client-get.sh

  chmod a+x  ${sc_generatedshdir}*.sh

  decho 3 "F:OUT:create_helper_scripts"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################################################################
# Start of the script main entry

starting=$(date);

# This environment is created to enable the MQ for Technical Sales Level 3 education
SECONDS=0

SCRIPTDIR="${MY_MQ_SCRIPTDIR}scripts/"
CONFIGDIR="${SCRIPTDIR}../config/"

MAINSCRIPTDIR="${SCRIPTDIR}../../../"

SC_SPACES_COUNTER=0
SC_SPACES_INCR=3

# parameters
sc_clnt="clnt1"

# load helper functions
. "${MAINSCRIPTDIR}"lib.sh

# load config file
read_config_file "${MAINSCRIPTDIR}properties/cp4i.properties"
read_config_file "${CONFIGDIR}mq.properties"

local lf_working_directory="${MY_MQ_GEN_CUSTOMDIR}"

create_project "${MY_MQ_DEMO_NAMESPACE}" "${MY_MQ_DEMO_NAMESPACE} project" "For MQ native HA and clustering demonstration" $lf_working_directory

# Create the certificates/secrets required for MQ Configuration
lf_namespace=${MY_MQ_DEMO_NAMESPACE}
lf_issuername=mq
lf_root_cert_name=mq
lf_tls_label1=mq-demo
# For TLS Certificate, name needs to be lower cases
lf_tls_certname=qm

create_certificate_chain $lf_namespace $lf_issuername $lf_root_cert_name $lf_tls_label1 $lf_tls_certname $lf_working_directory

export MY_MQ_DEMO_NAMESPACE
export MQ_CLUSTERNAME=cluster

export QMGR1=qm1
export QMGR2=qm2

# Ensure it is lower case
export QMGR1=$(echo "${QMGR1}" | tr '[:upper:]' '[:lower:]')
export QMGR2=$(echo "${QMGR2}" | tr '[:upper:]' '[:lower:]')
# Ensure it is upper case
export QMGR_UC1=$(echo "${QMGR1}" | tr '[:lower:]' '[:upper:]')
export QMGR_UC2=$(echo "${QMGR2}" | tr '[:lower:]' '[:upper:]')

local lf_source_directory="${MY_MQ_SCRIPTDIR}config/demo/"
local lf_target_directory="${MY_MQ_GEN_CUSTOMDIR}config/demo/"

# Create ConfigMap ini for QM
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="ConfigMap"
lf_cr_name=${MY_MQ_DEMO_NAMESPACE}-${MQ_CLUSTERNAME}-ini
lf_yaml_file="qms.ini.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Create ConfigMap MQSC common part for QM
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="ConfigMap"
lf_cr_name=${MY_MQ_DEMO_NAMESPACE}-${MQ_CLUSTERNAME}-mqsc-common
lf_yaml_file="queuedefs.cluster.mqsc.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

export QMGR=$QMGR1
# Create ConfigMap MQSC Channels for QM1

lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="ConfigMap"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-${MQ_CLUSTERNAME}-mqsc-${QMGR}"
lf_yaml_file="channels.mqsc.qm1.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Create ConfigMap for web access
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="ConfigMap"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-${QMGR}-mywebconfig"
lf_yaml_file="qm.webaccess.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Create QM
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="QueueManager"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-$QMGR"
lf_yaml_file="qmgr.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"
export QMGR=$QMGR2
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="ConfigMap"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-${MQ_CLUSTERNAME}-mqsc-${QMGR}"
lf_yaml_file="channels.mqsc.qm2.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Create ConfigMap for web access
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="ConfigMap"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-${QMGR}-mywebconfig"
lf_yaml_file="qm.webaccess.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Create QM
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="QueueManager"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-$QMGR"
lf_yaml_file="qmgr.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Create CCDT
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="QueueManager"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-$QMGR"
lf_yaml_file="ccdt.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

# Provides access to ccdt to application through http
lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="Deployment"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-ccdt-http-access"
lf_yaml_file="ccdt-http-access-dep.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

lf_namespace=$MY_MQ_DEMO_NAMESPACE
lf_type="Service"
lf_cr_name="${MY_MQ_DEMO_NAMESPACE}-ccdt-http-access"
lf_yaml_file="ccdt-http-access-svc.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2