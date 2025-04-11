#!/bin/bash
#####################################################################################################################
# Script using cert manager
#####################################################################################################################


#############################################################
function create_issuer () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_issuer
  
  create_oc_resource "Issuer" "${VAR_QMGR}-issuer" "${MY_MQ_SIMPLE_DEMODIR}tls/" "$MY_MQ_WORKINGDIR" "issuer.yaml" "${VAR_MQ_NAMESPACE}"

   trace_out $lf_tracelevel create_issuer
}

#############################################################
function create_qmgr_certificate () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr_certificate

  export VAR_ISSUER="${VAR_QMGR}-issuer"
  export VAR_SECRET="${VAR_QMGR}-secret"
  export VAR_LABEL="${VAR_QMGR}-label" 
  create_oc_resource "Certificate" "${VAR_QMGR}-cert" "${MY_MQ_SIMPLE_DEMODIR}tls/" "${MY_MQ_WORKINGDIR}" "ca_certificate.yaml" "$VAR_MQ_NAMESPACE"
  unset VAR_ISSUER VAR_SECRET VAR_LABEL

  trace_out $lf_tracelevel create_qmgr_certificate
}

#############################################################
function create_qmgr_configmaps () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr_configmaps

  create_oc_resource "ConfigMap" "$VAR_MQSC_OBJECTS_CM" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}" "qmgr_cm_mqsc.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "$VAR_AUTH_CM" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}" "qmgr_cm_mqsc_auth.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "$VAR_WEBCONFIG_CM" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}" "qmgr_cm_web.yaml" "$VAR_MQ_NAMESPACE"

  trace_out $lf_tracelevel create_qmgr_configmaps
}

#############################################################
function create_qmgr_route () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr_route

  create_oc_resource "Route" "${VAR_QMGR}-route" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}" "qmgr_route.yaml" "$VAR_MQ_NAMESPACE"

  trace_out $lf_tracelevel create_qmgr_route
}

#############################################################
function save_qmgr_tls () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel save_qmgr_tls

  save_certificate ${VAR_QMGR}-secret tls.crt ${sc_qmgr_srv_crtdir} $VAR_MQ_NAMESPACE
  save_certificate ${VAR_QMGR}-secret key.crt ${sc_qmgr_srv_crtdir} $VAR_MQ_NAMESPACE
  save_certificate ${VAR_QMGR}-secret ca.crt ${sc_qmgr_srv_crtdir} $VAR_MQ_NAMESPACE

  local lf_ca_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.ca.crt.pem"	
  local lf_srv_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.tls.crt.pem"
  local lf_srv_key="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.key.crt.pem"

  trace_out $lf_tracelevel save_qmgr_tls
}

#############################################################
function create_qmgr () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_qmgr

  # Use the new CRD MessagingServer(available since CP4I 16.1.0-SC2) 
  if $MY_MESSAGINGSERVER; then
    # Creating MQ MessagingServer instance
    create_operand_instance "MessagingServer" "${VAR_MSGSRV_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_MQ_WORKINGDIR}" "MessagingServer-Capability.yaml" "$VAR_MQ_NAMESPACE" "{.status.conditions[0].type}" "Ready"
  else 
    create_operand_instance "QueueManager" "${VAR_QMGR}" "${MY_MQ_SIMPLE_DEMODIR}tmpl" "${MY_MQ_WORKINGDIR}" "qmgr.yaml" "$VAR_MQ_NAMESPACE" "{.status.phase}" "Running"
  fi
  
  trace_out $lf_tracelevel create_qmgr
}

#################################################
# Create client key repository
#################################################
function create_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_clnt_kdb

  mylog "info" "Creating   : client key database for $VAR_CLNT1 to use with MQSSLKEYR env variable."

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${VAR_CLNT1}-keystore.p12";;
  esac  

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $VAR_KEYDB_TYPE -stash > /dev/null 2>&1  

  trace_out $lf_tracelevel create_clnt_kdb
}

#####################################################
# Create pki infrastructure : keys, certs, kdb, ....
#####################################################
function create_pki_cr () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_pki_cr

  ##-- Get the private/cert/ca for the Issuer cs-ca-issuer 
  #mylog "info" "Getting   : certificate and key for CA"
  #get_issuer_tls_resources

  ##-- Create the client key database 
  mylog "info" "Creating   : client key database for $VAR_CLNT1 to use with MQSSLKEYR env variable."
  create_clnt_kdb $VAR_MQ_NAMESPACE
  
  ##-- Add the queue manager's certificate to the client key database:
  mylog "info" "Adding     : qmgr certificate to the client key database"
  add_qmgr_crt_2_clnt_kdb $VAR_MQ_NAMESPACE
  
  ##-- Add CA crt to client kdb
  mylog "info" "Adding     : ca certificate to client kdb for $VAR_CLNT1"
  add_ca_crt_2_clnt_kdb $VAR_MQ_NAMESPACE

  trace_out $lf_tracelevel create_pki_cr
}

################################################
# Add qmgr certs to client keydb
#################################################
function add_qmgr_crt_2_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel add_qmgr_crt_2_clnt_kdb

  mylog "info" "Adding     : qmgr certificate to the client key database"

  save_certificate ${VAR_QMGR}-secret tls.crt ${sc_qmgr_srv_crtdir} $VAR_MQ_NAMESPACE
  local lf_srv_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.tls.crt.pem"
  
  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${VAR_CLNT1}-keystore.p12";;
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
#################################################
function add_ca_crt_2_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel add_ca_crt_2_clnt_kdb

  save_certificate ${VAR_QMGR}-secret ca.crt ${sc_qmgr_srv_crtdir} $VAR_MQ_NAMESPACE
  
  local lf_ca_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.ca.crt.pem"

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${VAR_CLNT1}-keystore.p12";;
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
  export ROOTURL=$(oc get route -n $VAR_MQ_NAMESPACE "${VAR_QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho $lf_tracelevel "VAR_CHL_UC=$VAR_CHL_UC|VAR_QMGR_UC=$VAR_QMGR_UC|ROOTURL=$ROOTURL"

  adapt_file "${MY_MQ_SIMPLE_DEMODIR}scripts/tmpl/json/" "${sc_qmgr_custom_gendir}json/" ccdt.json

  trace_out $lf_tracelevel create_ccdt
}

#############################################################
# Run this script natively (from terminal) 
#############################################################
function mq_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel mq_run_all
  
  create_issuer

  create_qmgr_certificate

  create_qmgr_configmaps

  create_qmgr_route

  # Create tls artifacts
  create_pki_cr

  create_qmgr

  # Create qmgr ccdt
  create_ccdt

  trace_out $lf_tracelevel mq_run_all
}

################################################
# initialisation
function mq_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel mq_init

  # Create namespace 
  create_project "$VAR_MQ_NAMESPACE" "$VAR_MQ_NAMESPACE project" "For MQ" "${MY_RESOURCESDIR}" "${MY_MQ_WORKINGDIR}"

  # Quick and dirty TODO
  export VAR_MQSC_OBJECTS_CM="${VAR_QMGR}-mqsc-cm"
  export MY_MQ_DEMO_NAMESPACE="${VAR_MQ_NAMESPACE}"

 
  check_directory_exist_create  "${MY_MQ_WORKINGDIR}generated/${VAR_QMGR}"
  sc_qmgr_custom_gendir="${MY_MQ_WORKINGDIR}generated/${VAR_QMGR}/"
  
  check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/${VAR_CLNT1}"
  sc_qmgr_clnt_crtdir="${sc_qmgr_custom_gendir}tls/${VAR_CLNT1}/"
  
  check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/qmgr"
  sc_qmgr_srv_crtdir="${sc_qmgr_custom_gendir}tls/qmgr/"
  
  # CCDT tmpl file
  sc_ccdt_tmpl_file="${MY_MQ_SIMPLE_DEMODIR}scripts/tmpl/json/ccdt.json";
  MQCCDTURL="${sc_qmgr_custom_gendir}json/ccdt.json"

  trace_out $lf_tracelevel mq_init
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
    --all) mq_run_all "$@";;
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

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./mq.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./mq.config.sh --all
################################################################################################

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
export MY_MQ_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/mq.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load config files
. "${sc_provision_constant_properties_file}"

# load config files
. "${sc_provision_variable_properties_file}"

# Load mq variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

mq_init

######################################################
# main entry
######################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi