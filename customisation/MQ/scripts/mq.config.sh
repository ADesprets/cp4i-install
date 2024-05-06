#!/bin/bash
#####################################################################################################################
# Prepare TLS repository, key, cert
# Think about using redirection : 2>&1 > Out-Null
# https://community.ibm.com/community/user/integration/blogs/atul-sharma/2022/01/06/ibm-mq-in-kubernetes-enabling-tls
# Site qui explique comment utiliser des CA dans TLS MQ
#####################################################################################################################

#####################################################
# Prepare self signed certificates for qmgr
#####################################################
function create_qmgr_ss_tls () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :create_qmgr_ss_tls"

  local lf_crt_file="${sc_srv_crtdir}qmgr-crt.pem"
  local lf_key_file="${sc_srv_crtdir}qmgr-key.pem"
  local lf_subject=${SUBJECT_SRV}
  
  # Generate the qmgr self signed certificate
  openssl x509 -req -newkey -days ${VALIDITY_DAYS}  rsa:${KEY_SIZE} -nodes -subj "${lf_subject}" -keyout $lf_key_file -out $lf_crt_file > /dev/null 2>&1

  decho "F:OUT:create_qmgr_ss_tls"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

#################################################
# Create client key repository
#################################################
function create_clnt_kdb () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :create_clnt_kdb"

  local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.p12"

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $KEYDB_TYPE -stash > /dev/null 2>&1  

  decho "F:OUT:create_clnt_kdb"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# Add qmgr certs to client keydb
#################################################
function add_qmgr_crt_2_clnt_kdb () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :add_qmgr_crt_2_clnt_kdb"

  local lf_clnt_keydb="${sc_clnt_crtdir}${sc_clnt}-keystore.p12"
  local lf_srv_crt="${sc_srv_crtdir}qmgr-crt.pem"

  # Add the queue manager public key to the client key database
	runmqakm -cert -add -db $lf_clnt_keydb -label $QMGR -file $lf_srv_crt -format ascii -stashed > /dev/null 2>&1

  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1

  decho "F:OUT:add_qmgr_crt_2_clnt_kdb"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

#####################################################
# Create pki infrastructure : keys, certs, kdb, ....
#####################################################
function create_pki_cr () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :create_pki_cr"

  ##-- Create a private key and a ca signed certificate for the queue manager
  mylog "info" "Creating   : certificate and key for qmgr $QMGR"
  create_qmgr_ss_tls

  ##-- Create the client key database 
  mylog "info" "Creating   : client key database for $sc_clnt to use with MQSSLKEYR env variable."
  create_clnt_kdb
  
  ##-- Add the queue manager's certificate to the client key database:
  mylog "info" "Adding     : qmgr certificate to the client key database"
  add_qmgr_crt_2_clnt_kdb
  
  decho "F:OUT:create_pki_cr"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# Create Openshift secret
################################################
function create_qmgr_secret () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :create_qmgr_secret"

  local lf_in_applyflag=$1    # ex: applyyamlflag  
  
  local lf_srv_crt="${sc_srv_crtdir}qmgr-crt.pem"
  local lf_srv_key="${sc_srv_crtdir}qmgr-key.pem"
  local lf_tmpl_file="${TMPLYAMLDIR}qmgr-secret_tmpl.yaml" 
  local lf_gen_file="${sc_generatedyamldir}qmgr-secret.yaml"

  export B64_QMGR_CRT=$(encode_b64_file $lf_srv_crt)
  export B64_QMGR_KEY=$(encode_b64_file $lf_srv_key)

  envsubst < ${lf_tmpl_file}  > ${lf_gen_file}

  # Apply
  case $lf_in_applyflag in
    y|Y)  oc apply -f $lf_gen_file ;;
  esac

  decho "F:OUT:create_qmgr_secret"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# Create Openshift qmgr
#################################################
function create_oc_qmgr () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :create_oc_qmgr"

  local lf_in_applyflag=$1

  local lf_tmpl_file="${TMPLYAMLDIR}qmgr_tmpl.yaml"
  local lf_gen_file="${sc_generatedyamldir}qmgr.yaml"
  
  envsubst < ${lf_tmpl_file}  > ${lf_gen_file}
 
  ##-- Creating MQ instances
  mylog "info" "Creating   : ${QMGR}/QueueManager"

  # Apply
  oc apply -f $lf_gen_file 
  lf_octype="QueueManager"
  lf_ocstate="Running"
  lf_ocpath=".status.phase"
  lf_msg="$lf_octype $QMGR $lf_ocpath is $lf_ocstate"
  lf_command="oc get ${lf_octype} ${QMGR} -n ${OC_PROJECT} --output json|jq -r ${lf_ocpath}"
  
  decho "lf_octype=$lf_octype|lf_ocstate=$lf_ocstate|lf_ocpath=$lf_ocpath|lf_msg=$lf_msg|lf_command=$lf_command"
  
  wait_for_state "${lf_msg}" "${lf_ocstate}" "${lf_command}"
   # Generate ccdt file
  mylog "info" "Creating   : ccdt file to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  export ROOTURL=$(oc get route -n $OC_PROJECT "${QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho "ROOTURL=$ROOTURL"

  create_ccdt

  decho "F:OUT:create_oc_qmgr"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# Create Openshift CCDT file
################################################
function create_ccdt () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:INT:create_ccdt"
 
  # check for the existence of all needed files 
  check_file_exist $sc_ccdt_tmpl_file
  envsubst < ${sc_ccdt_tmpl_file}  > ${MQCCDTURL}

  decho "F:OUT:create_ccdt"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# Delete Openshift Custom Resource
################################################
function delete_oc_qmgr () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :delete_oc_qmgr"

  # SB]20221125 prévoir aussi la suppression des pvc en cas de storage persistent  

  local lf_gen_file="${sc_generatedyamldir}qmgr.yaml"

  oc -n ${OC_PROJECT} delete -f ${lf_gen_file}

  decho "F:OUT:delete_oc_qmgr"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################################################################
# Start of the script main entry
################################################################################################

# end with / on purpose
#MAINSCRIPTDIR="${PWD}/"
OPENSSLDIR="${MAINSCRIPTDIR}openssl/"
#PRIVATEDIR="${MAINSCRIPTDIR}private/"
#VERSIONSDIR="${MAINSCRIPTDIR}versions/"
TMPLJSONDIR="${MAINSCRIPTDIR}tmpl/json/"
TMPLSCRIPTDIR="${MAINSCRIPTDIR}tmpl/script/"
TMPLYAMLDIR="${MAINSCRIPTDIR}tmpl/yaml/"

# SB]20240404 Global Index sequence for incremental output for each function call
sc_spaces_counter=0
sc_spaces_incr=3

sc_script=$0

## load helper functions
. ${MAINSCRIPTDIR}lib.sh

# parameters
QMGR="${MY_MQ_INSTANCE_NAME}"
sc_clnt="clnt1"
sc_config_file="${MAINSCRIPTDIR}cp4i.properties"

# I have to get first the qmgr name because it's used in the following configfile
export QMGR=$(echo "${sc_srv}"| tr '[:upper:]' '[:lower:]')
export QMGR_UC=$(echo $QMGR | tr '[:lower:]' '[:upper:]')
export CLNT1="${sc_clnt}"

##-- check existence of configfile and versionfile
check_config_and_version_files $sc_config_file $sc_versions_file

check_directory_exist_create  "${MAINSCRIPTDIR}generated/${QMGR}"
sc_generateddir="${MAINSCRIPTDIR}generated/${QMGR}/"

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

check_directory_exist_create  "${sc_generateddir}script"
sc_generatedscriptdir="${sc_generateddir}script/"

# CCDT tmpl file
sc_ccdt_tmpl_file="${TMPLJSONDIR}ccdt_tmpl.json";
MQCCDTURL="${sc_generatedjsondir}ccdt.json"

case $sc_option in
  -d) mylog "info" "Clean part"
      if [ $sc_nbargs -ne 5 ]; then
        print_help
        exit 1
      fi

      delete_oc_qmgr
      ;;

  -i) mylog "info" "Installation part"
      decho "sc_nbargs=$sc_nbargs"
      if [ $sc_nbargs -ne 5 ]; then
        print_help
        exit 1
      fi

      # Create PKI resources for qmgr and client
      create_pki_cr

      # Create openshift resources for qmgr (secrets, cm, qmgr, route, ....)
      create_oc_qmgr
      ;;  
esac
################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}../config/"
MAINSCRIPTDIR="${scriptdir}../../../"

# load helper functions
. "${MAINSCRIPTDIR}"lib.sh

read_config_file "${MAINSCRIPTDIR}cp4i.properties"
read_config_file "${configdir}mq.properties"

# Creation d'un Queue Manager
SECONDS=0
check_create_oc_yaml "QueueManager" "QM1" "${configdir}QM1.yaml" $mq_project
check_resource_availability "QueueManager" "${mq_instance_name}-qm1" $mq_project
wait_for_state QueueManager "${mq_instance_name}-qm1" "Running" '.status.phase' $mq_project
duration=$SECONDS
mylog info "Creation of the Queue Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2