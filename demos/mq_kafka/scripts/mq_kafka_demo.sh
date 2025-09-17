#!/bin/bash
#####################################
# Script using cert manager
################################################


################################################
function create_issuer () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_issuer
  
  create_oc_resource "Issuer" "${VAR_QMGR}-issuer" "${MY_YAMLDIR}tls/" "${sc_mq_kafka_demo_workingdir}" "Issuer_ca.yaml" "${VAR_MQ_NAMESPACE}"

   trace_out $lf_tracelevel create_issuer
}

################################################
function create_qmgr_certificate () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr_certificate

  export VAR_CERT_ISSUER="${VAR_QMGR}-issuer"
  export VAR_SECRET="${VAR_QMGR}-secret"
  export VAR_CERT_LABEL="${VAR_QMGR}-label" 
  create_oc_resource "Certificate" "${VAR_QMGR}-cert" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_ca_certificate.yaml" "$VAR_MQ_NAMESPACE"
  unset VAR_CERT_ISSUER VAR_SECRET VAR_CERT_LABEL

  trace_out $lf_tracelevel create_qmgr_certificate
}

################################################
# Function to process array of (object id, yaml file)
# @param 1: type
# @param 2: dir: the source directory
# @param 3: dir: the target directory 
# @param 4: namespace: the namespace
# @param 5: array

function create_oc_objects() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_oc_objects
  
  local lf_in_type="$1"
  local lf_in_source_directory="$2"
  local lf_in_target_directory="$3"
  local lf_in_namespace=$4
  local -n lf_in_arr_ref=$5
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|"

  local lf_length=${#lf_in_arr_ref[@]}
  local lf_cm_id, lf_in_file

  # Ensure the array contains an even number of elements
  if (( lf_length % 2 != 0 )); then
    mylog error "Error: Odd number of elements in the array. Ensure pairs are complete."
    trace_out $lf_tracelevel create_oc_objects
    exit 1
  fi

  # Loop through array in pairs
  for ((i = 0; i < lf_length; i += 2)); do
    lf_cm_id=${lf_in_arr_ref[i]}
    lf_file=${lf_in_arr_ref[i+1]}
    create_oc_resource "$lf_in_type" "$lf_cm_id" "${lf_in_source_directory}" "${lf_in_target_directory}" "$lf_file" "${lf_in_namespace}"
  done
  
  trace_out $lf_tracelevel create_oc_objects
}

################################################
function create_qmgr_configmaps_old () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr_configmaps_old

  create_oc_resource "ConfigMap" "$VAR_MQSC_OBJECTS_CM" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_mqsc_objects.yaml" "${VAR_MQ_NAMESPACE}"
  create_oc_resource "ConfigMap" "$VAR_MQSC_LDAP_CM" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_mqsc_ldap.yaml" "${VAR_MQ_NAMESPACE}"
  #create_oc_resource "ConfigMap" "$VAR_AUTH_CM" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_auth_v3.yaml" "${VAR_MQ_NAMESPACE}"
  #create_oc_resource "ConfigMap" "$VAR_JMS_CM" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_jms_v3.yaml" "${VAR_MQ_NAMESPACE}"
  #create_oc_resource "ConfigMap" "$VAR_INI_CM" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_ini_v3.yaml" "${VAR_MQ_NAMESPACE}"
  create_oc_resource "ConfigMap" "$VAR_WEBCONFIG_CM" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_webconfig.yaml" "${VAR_MQ_NAMESPACE}"

  trace_out $lf_tracelevel create_qmgr_configmaps_old
}

################################################
function create_qmgr_route () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr_route

  create_oc_resource "Route" "${VAR_QMGR}-route" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_route.yaml" "${VAR_MQ_NAMESPACE}"

  trace_out $lf_tracelevel create_qmgr_route
}

################################################
function save_qmgr_tls () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel save_qmgr_tls

  save_certificate ${VAR_QMGR}-secret tls.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  save_certificate ${VAR_QMGR}-secret key.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  save_certificate ${VAR_QMGR}-secret ca.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE

  local lf_ca_crt="${sc_mq_kafka_demo_workingdir}${VAR_QMGR}-secret.ca.crt.pem"	
  local lf_srv_crt="${sc_mq_kafka_demo_workingdir}${VAR_QMGR}-secret.tls.crt.pem"
  local lf_srv_key="${sc_mq_kafka_demo_workingdir}${VAR_QMGR}-secret.key.crt.pem"

  trace_out $lf_tracelevel save_qmgr_tls
}

################################################
function create_qmgr () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr

  local lf_in_file=$1

  decho $lf_tracelevel "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument: yaml file"
    trace_out $lf_tracelevel create_qmgr
    exit  1
  fi

  # Use the new CRD MessagingServer(available since CP4I 16.1.0-SC2) 
  if $MY_MESSAGINGSERVER; then
    # Creating MQ MessagingServer instance
    create_operand_instance "MessagingServer" "${VAR_MSGSRV_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_MQ_WORKINGDIR}" "MessagingServer-Capability.yaml" "$VAR_MQ_NAMESPACE" "{.status.conditions[0].type}" "Ready"
  else 
    create_operand_instance "QueueManager" "${VAR_QMGR}" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "${lf_in_file}" "$VAR_MQ_NAMESPACE" "{.status.phase}" "Running"
  fi

  
  trace_out $lf_tracelevel create_qmgr
}

################################################
# Create client key repository
################################################
function create_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_clnt_kdb

  mylog "info" "Creating   : client key database for $VAR_CLNT1 to use with MQSSLKEYR env variable."

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_mq_kafka_demo_workingdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_mq_kafka_demo_workingdir}${VAR_CLNT1}-keystore.p12";;
  esac  

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $VAR_KEYDB_TYPE -stash > /dev/null 2>&1  

  trace_out $lf_tracelevel create_clnt_kdb
}

################################################
# Create pki infrastructure : keys, certs, kdb, ....
################################################
function create_pki_cr () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_pki_cr

  ##-- Get the private/cert/ca for the Issuer cs-ca-issuer 
  #mylog "info" "Getting   : certificate and key for CA"
  #get_issuer_tls_resources

  ##-- Create the client key database 
  create_clnt_kdb
  
  ##-- Add the queue manager's certificate to the client key database:
  add_qmgr_crt_2_clnt_kdb
  
  ##-- Add CA crt to client kdb
  add_ca_crt_2_clnt_kdb

  trace_out $lf_tracelevel create_pki_cr
}

################################################
# Add qmgr certs to client keydb
################################################
function add_qmgr_crt_2_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel add_qmgr_crt_2_clnt_kdb

  mylog "info" "Adding     : qmgr certificate to the client key database"

  save_certificate ${VAR_QMGR}-secret tls.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  local lf_srv_crt="${sc_mq_kafka_demo_workingdir}${VAR_QMGR}-secret.tls.crt.pem"
  
  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_mq_kafka_demo_workingdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_mq_kafka_demo_workingdir}${VAR_CLNT1}-keystore.p12";;
  esac  

  #decho $lf_tracelevel "lf_clnt_keydb=$lf_clnt_keydb|lf_srv_crt=$lf_srv_crt"

  # Add the queue manager public key to the client key database
	runmqakm -cert -add -db $lf_clnt_keydb -label $VAR_QMGR -file $lf_srv_crt -format ascii -stashed > /dev/null 2>&1

  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1

  trace_out $lf_tracelevel add_qmgr_crt_2_clnt_kdb
}

################################################
# Add ca cert to client keydb
################################################
function add_ca_crt_2_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel add_ca_crt_2_clnt_kdb

  mylog "info" "Adding     : ca certificate to client kdb for $VAR_CLNT1"
  
  save_certificate ${VAR_QMGR}-secret ca.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  
  local lf_ca_crt="${sc_mq_kafka_demo_workingdir}${VAR_QMGR}-secret.ca.crt.pem"

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_mq_kafka_demo_workingdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_mq_kafka_demo_workingdir}${VAR_CLNT1}-keystore.p12";;
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

  trace_out $lf_tracelevel add_ca_crt_2_clnt_kdb
}

################################################
# Create Openshift CCDT file
################################################
function create_ccdt () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_ccdt

  # Generate ccdt file
  mylog "info" "Creating   : ccdt file to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  export ROOTURL=$($MY_CLUSTER_COMMAND get route -n $VAR_MQ_NAMESPACE "${VAR_QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho $lf_tracelevel "VAR_CHL_UC=$VAR_CHL_UC|VAR_QMGR_UC=$VAR_QMGR_UC|ROOTURL=$ROOTURL"

  adapt_file "${sc_mq_kafka_demo_json_dir}" "${sc_mq_kafka_demo_workingdir}" ccdt.json

  trace_out $lf_tracelevel create_ccdt
}

################################################
# Demo : MQ, Kafka
function mq_kafka_demo_generate_certs() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel mq_kafka_demo_generate_certs

  # Create Issuer, CA Certificate, MQ Server cert, JMS client cert, kafka client cert
  #create_oc_resource "Issuer" "${VAR_QMGR}-issuer" "${sc_mq_kafka_demo_tls_dir}" "${sc_mq_kafka_demo_workingdir}" "issuer.yaml" "$VAR_MQ_NAMESPACE"
  export VAR_CERT_ISSUER="${VAR_QMGR}-issuer"
  export VAR_SECRET="${VAR_QMGR}-secret"
  export VAR_CERT_LABEL="ca-root-cert-label" 
  create_oc_resource "Certificate" "ca-root-cert" "${sc_mq_kafka_demo_tls_dir}" "${sc_mq_kafka_demo_workingdir}" "ca_certificate.yaml" "$VAR_MQ_NAMESPACE"
  unset VAR_CERT_ISSUER VAR_SECRET VAR_CERT_LABEL

  export VAR_CERT_ISSUER="${VAR_QMGR}-issuer"
  export VAR_SECRET="${VAR_QMGR}-secret"
  export VAR_CERT_LABEL="${VAR_QMGR}-label" 
  create_oc_resource "Certificate" "${VAR_QMGR}" "${sc_mq_kafka_demo_tls_dir}" "${sc_mq_kafka_demo_workingdir}" "mq_server_certificate.yaml" "$VAR_MQ_NAMESPACE"
  unset VAR_CERT_ISSUER VAR_SECRET VAR_CERT_LABEL

  export VAR_CERT_ISSUER="${VAR_QMGR}-issuer"
  export VAR_SECRET="${VAR_QMGR}-secret"
  export VAR_CERT_LABEL="jms-client-cert-label" 
  create_oc_resource "Certificate" "jms-client-cert" "${sc_mq_kafka_demo_tls_dir}" "${sc_mq_kafka_demo_workingdir}" "jms_client_certificate.yaml" "$VAR_MQ_NAMESPACE"
  unset VAR_CERT_ISSUER VAR_SECRET VAR_CERT_LABEL

  export VAR_CERT_ISSUER="${VAR_QMGR}-issuer"
  export VAR_SECRET="${VAR_QMGR}-secret"
  export VAR_CERT_LABEL="kafka-client-cert-label" 
  create_oc_resource "Certificate" "kafka-client-cert" "${sc_mq_kafka_demo_tls_dir}" "${sc_mq_kafka_demo_workingdir}" "kafka_client_certificate.yaml" "$VAR_MQ_NAMESPACE"
  unset VAR_CERT_ISSUER VAR_SECRET VAR_CERT_LABEL


  #save_certificate ca-root-cert-secret tls.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate ca-root-cert-secret key.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate ca-root-cert-secret ca.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE

  #save_certificate ${VAR_QMGR}-secret tls.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate ${VAR_QMGR}-secret key.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate ${VAR_QMGR}-secret ca.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE

  #save_certificate jms-client-cert-secret tls.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate jms-client-cert-secret key.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate jms-client-cert-secret ca.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE

  #save_certificate kafka-client-cert-secret tls.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate kafka-client-cert-secret key.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE
  #save_certificate kafka-client-cert-secret ca.crt ${sc_mq_kafka_demo_workingdir} $VAR_MQ_NAMESPACE

  trace_out $lf_tracelevel mq_kafka_demo_generate_certs
}

################################################
# Create Kafka topic
function create_kafka_topic() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_kafka_topic

  export VAR_ES_TOPIC_NAME="commands.topic"
  export VAR_ES_SPEC_TOPIC_NAME="MQ.COMMANDS"
  export VAR_ES_SPEC_TOPIC_PARTITION=1
  export VAR_ES_SPEC_TOPIC_REPLICA=3
  
  # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
  create_oc_resource "KafkaTopic" "${VAR_ES_TOPIC_NAME}" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "topic.yaml" "$VAR_MQ_NAMESPACE"

  trace_out $lf_tracelevel create_kafka_topic
}

################################################
# Create Kafka user
function create_kafka_user() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_kafka_user

  # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
  create_operand_instance "KafkaUser" "kafka-connect-credentials" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "kafka_creds.yaml" "$VAR_MQ_NAMESPACE" "'{.status.conditions[?(@.type=="Ready")].status}'" "True"
  
  trace_out $lf_tracelevel create_kafka_user
}

################################################
# Create mq secret to be used by the connector
function create_mq_creds() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_mq_creds
  
  create_oc_resource "Secret" "mq-credentials" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "mq_creds.yaml" "$VAR_MQ_NAMESPACE"

  trace_out $lf_tracelevel create_mq_creds
}

################################################
# Function to process calls
function process_calls() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel process_calls

  local lf_in_calls="$1"  # Get the full string of calls and parameters

  local lf_commands    # Array to store the commands
  local lf_cmd         # Command to process
  local lf_func        # Function name
  local lf_params      # Parameters
  local lf_list        # List of available functions


    # Split the calls by comma and loop through each
    IFS=',' read -ra lf_commands <<< "$lf_in_calls"
    for lf_cmd in "${lf_commands[@]}"; do
      # Trim leading/trailing spaces from the command
      #lf_cmd=$(echo "$lf_cmd" | xargs)
      lf_cmd=$(echo "$lf_cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')

      # Extract the function name and parameters
      lf_func=$(echo "$lf_cmd" | awk '{print $1}')
      lf_params=$(echo "$lf_cmd" | awk '{$1=""; sub(/^ /, ""); print}')  # Get all the parameters after the function name
      decho $lf_tracelevel "Function: $lf_func|Parameters: $lf_params"

      # Check if the function exists and call it
      if declare -f "$lf_func" > /dev/null; then
        if [ "$lf_func" = "main" ] || [ "$lf_func" = "process_calls" ]; then
          mylog error "Functions 'main', 'process_calls' cannot be called."
          trace_out $lf_tracelevel process_calls
          return 1
        fi
        #provision_cluster_init
        $lf_func $lf_params
      else
        mylog error "Function '$lf_func' not found."
        # lf_list=$(grep -E '^\s*(function\s+\w+|\w+\s*\(\))' $(basename "$0") | sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\2/')
        lf_list=$(declare -F | awk '{print $NF}')
        mylog info "Available functions are:" 0
        mylog info "$lf_list" 0

        trace_out $lf_tracelevel process_calls
        return 1
      fi
    done

  trace_out $lf_tracelevel process_calls
}

################################################
# Run this script natively (from terminal) 
################################################
function mq_kafka_demo_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel mq_kafka_demo_run_all

  SECONDS=0
  local lf_starting_date=$(date);

  check_directory_exist_create "${sc_mq_kafka_demo_workingdir}"
  create_project "${VAR_MQ_NAMESPACE}" "${VAR_MQ_NAMESPACE} project" "For MQ Kafka Demo" "${MY_RESOURCESDIR}" "${sc_mq_kafka_demo_workingdir}"  

  # This demo is based on the following one :  https://github.com/dalelane/mq-kafka-connect-tutorial
  # in case it's not already installed (happy with idempotence !!!)
  #${PROVISION_SCRIPTDIR}provision_cluster-v3.sh --call install_openldap, customise_openldap, install_mq, install_es $VAR_ES_NAMESPACE
  ${PROVISION_SCRIPTDIR}provision_cluster-v2.sh --call install_openldap, customise_openldap
  
  # Get ldap properties (DN, user, password, ...)
  read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
  load_users_2_ldap_server "${sc_mq_kafka_demo_ldap_dir}" ${sc_mq_kafka_demo_workingdir} "ldap_users_demo_mq_kafka.ldif"
  
  # Generate certificates
  mq_kafka_demo_generate_certs

  # Create qmgr configmaps
  sc_cm_pairs=("$VAR_MQSC_OBJECTS_CM" "qmgr_cm_mqsc_objects.yaml" "$VAR_MQSC_LDAP_CM" "qmgr_cm_mqsc_ldap.yaml" "$VAR_WEBCONFIG_CM" "qmgr_cm_webconfig.yaml")
  create_oc_objects "ConfigMap" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "${VAR_MQ_NAMESPACE}" sc_cm_pairs

  # Create qmgr route
  create_qmgr_route

  # Create qmgr
  create_qmgr "qmgr_initial.yaml"

  # Create tls artifacts
  create_pki_cr

  # Create qmgr ccdt
  create_ccdt

  # Modify the MQ queue manager to prepare it for the Connector
  #create_oc_resource "ConfigMap" "$VAR_MQSC_MODIFY" "${sc_mq_kafka_demo_yaml_dir}" "${sc_mq_kafka_demo_workingdir}" "qmgr_cm_mqsc_modify.yaml" "${sc_mq_kafka_demo_workingdir}
  sc_cm_pairs=("$VAR_MQSC_MODIFY" "qmgr_cm_mqsc_modify.yaml")
  create_oc_objects sc_cm_pairs
  create_qmgr "qmgr_modify.yaml"

  ## Create kafka topic
  #create_kafka_topic

  ## Creating Event Streams credentials that the Connector will use to access Kafka
  #create_kafka_user
  
  ## Storing MQ credentials that the Connector will use to access MQ
  #create_mq_creds 

  local lf_ending_date=$(date)
   mylog info "==== Creation of the Queue Manager [ended : $lf_ending_date and took : $SECONDS seconds]." 0  

  trace_out $lf_tracelevel mq_kafka_demo_run_all
}

################################################
# initialisation
function mq_kafka_demo_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel mq_kafka_demo_init

  # Directories
  sc_mq_kafka_demo_tls_dir="${sc_component_script_dir}tls/"
  sc_mq_kafka_demo_ldap_dir="${sc_component_script_dir}ldap/"
  sc_mq_kafka_demo_json_dir="${sc_component_script_dir}tmpl/json/"
  sc_mq_kafka_demo_sh_dir="${sc_component_script_dir}tmpl/sh/"
  sc_mq_kafka_demo_yaml_dir="${sc_component_script_dir}tmpl/yaml/"
  sc_mq_kafka_demo_workingdir="${sc_component_script_dir}working/${VAR_QMGR}/"
  
  check_directory_exist_create  "${sc_mq_kafka_demo_workingdir}"
  
  ## CCDT tmpl file
  sc_ccdt_tmpl_file="${MY_MQ_SIMPLE_DEMODIR}/tmpl/json/ccdt.json";
  MQCCDTURL="${sc_mq_kafka_demo_workingdir}ccdt.json"

  trace_out $lf_tracelevel mq_kafka_demo_init
}

################################################
# main function
# Main logic
function main() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel main

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    return 1
  fi

  # Main script logic
  local lf_calls=""  # Initialize calls variable
  local lf_key

  while [[ $# -gt 0 ]]; do
    lf_key="$1"
    case $lf_key in
      --all)
        shift
        ;;
      --call)
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          lf_calls+="$1 "  # Accumulate all arguments after --call
          shift
        done
        ;;
      *)
        mylog error "Invalid option '$1'. Use --all or --call function_name parameters, function_name parameters, ...."
        trace_out $lf_tracelevel main
        return 1
        ;;
      esac
  done
  lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces

  # Call processing function if --call was used
  case $lf_key in
    --all) mq_kafka_demo_run_all "$@";;
    --call) if [[ -n $lf_calls ]]; then
              process_calls "$lf_calls"
            else
              mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
              trace_out $lf_tracelevel main
              return 1
            fi;;
    esac

  trace_out $lf_tracelevel main
  exit 0
}

#################################
# Start of the script main entry
#################################
# other example: ./mq_kafka_demo.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./mq_kafka_demo.config.sh --all
#################################

# SB] getting the path of this script independently from using it directly or calling it from another script
# sc_component_script_dir="$( cd "$( dirname "$0" )" && pwd )/": this statement returns the calling script path

# Voir aussi comment on peut utiliser l'option suivante (trouvée dans un sript de Dale Lane)
# allow this script to be run from other locations, despite the
# relative file paths used in it
#OPTION# if [[ $BASH_SOURCE = */* ]]; then
#OPTION#   cd -- "${BASH_SOURCE%/*}/" || exit
#OPTION# fi

# the following script returns the absolute path of this script independently from using it directly or calling it from another script
sc_component_script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"
#export MY_MQ_KAFKA_DEMO_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}/properties/mq_kafka_demo.properties"

# SB]20250319 Je suis obligé d'utiliser set -a (unset) et set +a (set) par ce que à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters file
set -a
. "${sc_provision_script_parameters_file}"

# load resources files
. "${sc_provision_constant_properties_file}"

# Load mq variables
. $sc_component_properties_file

# Load shared variables
if [[ ! -e $MY_USEFUL_INFOS_FILE ]]; then
  echo "No such file: $MY_USEFUL_INFOS_FILE" 1>&2
  echo "You have to provide such file : $MY_USEFUL_INFOS_FILE"
  echo "a sample can be found here : ${PROVISION_SCRIPTDIR}sample_useful_infos.properties"
  exit 1
fi
. $MY_USEFUL_INFOS_FILE
set +a

# load helper functions
. ${sc_provision_lib_file}

mq_kafka_demo_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi