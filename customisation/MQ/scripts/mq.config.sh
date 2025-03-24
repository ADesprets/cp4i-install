#!/bin/bash
#####################################################################################################################
# Script using cert manager
#####################################################################################################################


#############################################################
function create_issuer () {
  trace_in 3 create_issuer
  
  create_oc_resource "Issuer" "${VAR_QMGR}-issuer" "${MY_RESOURCESDIR}" "$MY_MQ_WORKINGDIR" "self-signed-issuer.yaml" "${VAR_MQ_NAMESPACE}"

   trace_out 3 create_issuer
}

#############################################################
function create_qmgr_certificate () {
  trace_in 3 create_qmgr_certificate
  
  create_oc_resource "Certificate" "${VAR_QMGR}-cert" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr_CACertificate.yaml" "$VAR_MQ_NAMESPACE"

  trace_out 3 create_qmgr_certificate
}

#############################################################
function create_qmgr_configmaps () {
  trace_in 3 create_qmgr_configmaps

  create_oc_resource "ConfigMap" "$VAR_MQSC_CM" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr_cm_mqsc.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "$VAR_WEBCONFIG_CM" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr_cm_web.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "$VAR_AUTH_CM" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr_cm_mqsc_auth.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "$VAR_INI_CM" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr_cm_ini.yaml" "$VAR_MQ_NAMESPACE"

  trace_out 3 create_qmgr_configmaps
}

#############################################################
function create_qmgr_route () {
  trace_in 3 create_qmgr_route

  create_oc_resource "Route" "${VAR_QMGR}-route" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr_route.yaml" "$VAR_MQ_NAMESPACE"

  trace_out 3 create_qmgr_route
}

#############################################################
function save_qmgr_tls () {
  trace_in 3 save_qmgr_tls

  save_certificate $VAR_MQ_NAMESPACE ${VAR_QMGR}-secret tls.crt ${sc_qmgr_srv_crtdir}
  save_certificate $VAR_MQ_NAMESPACE ${VAR_QMGR}-secret key.crt ${sc_qmgr_srv_crtdir}
  save_certificate $VAR_MQ_NAMESPACE ${VAR_QMGR}-secret ca.crt ${sc_qmgr_srv_crtdir}

  local lf_ca_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.ca.crt.pem"	
  local lf_srv_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.tls.crt.pem"
  local lf_srv_key="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.key.crt.pem"

  trace_out 3 save_qmgr_tls
}

#############################################################
function create_qmgr () {
  trace_in 3 create_qmgr

  # Use the new CRD MessagingServer(available since CP4I 16.1.0-SC2) 
  if $MY_MESSAGINGSERVER; then
    # Creating MQ MessagingServer instance
    create_operand_instance "MessagingServer" "${VAR_MSGSRV_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_MQ_WORKINGDIR}" "MessagingServer-Capability.yaml" "$VAR_MQ_NAMESPACE" "{.status.conditions[0].type}" "Ready"
  else 
    create_operand_instance "QueueManager" "${VAR_QMGR}" "${sc_mq_tmpl_yaml_dir}" "${MY_MQ_WORKINGDIR}" "qmgr.yaml" "$VAR_MQ_NAMESPACE" "{.status.phase}" "Running"
  fi
  
  trace_out 3 create_qmgr
}

#################################################
# Create client key repository
#################################################
function create_clnt_kdb () {
  trace_in 3 create_clnt_kdb

  mylog "info" "Creating   : client key database for $CLNT1 to use with MQSSLKEYR env variable."

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${CLNT1}-keystore.p12";;
  esac  

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $VAR_KEYDB_TYPE -stash > /dev/null 2>&1  

  trace_out 3 create_clnt_kdb
}

#####################################################
# Create pki infrastructure : keys, certs, kdb, ....
#####################################################
function create_pki_cr () {
  trace_in 3 create_pki_cr

  ##-- Get the private/cert/ca for the Issuer cs-ca-issuer 
  #mylog "info" "Getting   : certificate and key for CA"
  #get_issuer_tls_resources

  ##-- Create the client key database 
  mylog "info" "Creating   : client key database for $CLNT1 to use with MQSSLKEYR env variable."
  create_clnt_kdb $VAR_MQ_NAMESPACE
  
  ##-- Add the queue manager's certificate to the client key database:
  mylog "info" "Adding     : qmgr certificate to the client key database"
  add_qmgr_crt_2_clnt_kdb $VAR_MQ_NAMESPACE
  
  ##-- Add CA crt to client kdb
  mylog "info" "Adding     : ca certificate to client kdb for $CLNT1"
  add_ca_crt_2_clnt_kdb $VAR_MQ_NAMESPACE

  trace_out 3 create_pki_cr
}

################################################
# Add qmgr certs to client keydb
#################################################
function add_qmgr_crt_2_clnt_kdb () {
  trace_in 3 add_qmgr_crt_2_clnt_kdb

  mylog "info" "Adding     : qmgr certificate to the client key database"

  save_certificate $VAR_MQ_NAMESPACE ${VAR_QMGR}-secret tls.crt ${sc_qmgr_srv_crtdir}
  local lf_srv_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.tls.crt.pem"
  
  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${CLNT1}-keystore.p12";;
  esac  

  #decho 3 "lf_clnt_keydb=$lf_clnt_keydb|lf_srv_crt=$lf_srv_crt"

  # Add the queue manager public key to the client key database
	runmqakm -cert -add -db $lf_clnt_keydb -label $VAR_QMGR -file $lf_srv_crt -format ascii -stashed > /dev/null 2>&1

  # Check. List the database certificates:
  mylog "info" "listing    : certificates in keydb : $lf_clnt_keydb"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1

  trace_out 3 add_qmgr_crt_2_clnt_kdb
}

################################################
# Add ca cert to client keydb
#################################################
function add_ca_crt_2_clnt_kdb () {
  trace_in 3 add_ca_crt_2_clnt_kdb

  save_certificate $VAR_MQ_NAMESPACE ${VAR_QMGR}-secret ca.crt ${sc_qmgr_srv_crtdir}
  
  local lf_ca_crt="${sc_qmgr_srv_crtdir}${VAR_QMGR}-secret.ca.crt.pem"

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${CLNT1}-keystore.p12";;
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

  trace_out 3 add_ca_crt_2_clnt_kdb
}

################################################
# Create Openshift CCDT file
################################################
function create_ccdt () {
  trace_in 3 create_ccdt
 
  # Generate ccdt file
  mylog "info" "Creating   : ccdt file to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  export ROOTURL=$(oc get route -n $VAR_MQ_NAMESPACE "${VAR_QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho 3 "VAR_CHL_UC=$VAR_CHL_UC|VAR_QMGR_UC=$VAR_QMGR_UC|ROOTURL=$ROOTURL"

  adapt_file "${MY_MQ_SCRIPTDIR}scripts/tmpl/json/" "${sc_qmgr_custom_gendir}json/" ccdt.json

  trace_out 3 create_ccdt
}

#############################################################
# Run this script natively (from terminal) 
#############################################################
function mq_run_all () {
  trace_in 3 mq_run_all

  SECONDS=0
  local lf_starting_date=$(date);

  mylog info "==== Customise MQ." 0

  check_directory_exist_create "${VAR_MQ_WORKINGDIR}"
  
  # Create namespace 
  create_project "$VAR_MQ_NAMESPACE" "$VAR_MQ_NAMESPACE project" "For MQ customisation" "${MY_RESOURCESDIR}" "${VAR_MQ_WORKINGDIR}"

  # Create Issuer
  create_issuer

  # Create qmgr certificate
  create_qmgr_certificate

  # Create qmgr configmaps
  create_qmgr_configmaps

  # Create qmgr route
  create_qmgr_route

  # Create qmgr
  create_qmgr

  # Create tls artifacts
  create_pki_cr

  # Create qmgr ccdt
  create_ccdt

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
    
  mylog info "==== Customisation of mq [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  trace_out 3 mq_run_all
}

################################################
# initialisation
function mq_init() {
  trace_in 2 mq_init

  ### Dynamic environment variables
  export VAR_QMGR=$(echo "${VAR_MQ_INSTANCE_NAME}"| tr '[:upper:]' '[:lower:]')
  export VAR_QMGR_UC=$(echo $VAR_QMGR | tr '[:lower:]' '[:upper:]')
  export CLNT1="clnt1"
  export VAR_CHL="${VAR_QMGR}chl"
  export VAR_CHL_UC=$(echo $VAR_CHL | tr '[:lower:]' '[:upper:]')
  export VAR_MQSC_CM="${VAR_QMGR}-mqsc-cm"
  export VAR_AUTH_CM="${VAR_QMGR}-auth-cm"
  export VAR_WEBCONFIG_CM="${VAR_QMGR}-webconfig-cm"
  export VAR_INI_CM="${VAR_QMGR}-ini-cm"

  # Template directories
  #sc_mq_tmpl_json_dir="${sc_component_script_dir}tmpl/json/"
  #sc_mq_tmpl_sh_dir="${sc_component_script_dir}tmpl/sh/"
  sc_mq_tmpl_yaml_dir="${sc_component_script_dir}tmpl/yaml/"
  
  check_directory_exist_create  "${MY_MQ_GEN_CUSTOMDIR}generated/${VAR_QMGR}"
  sc_qmgr_custom_gendir="${MY_MQ_GEN_CUSTOMDIR}generated/${VAR_QMGR}/"
  
  #check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/ca"
  #sc_qmgr_ca_crtdir="${sc_qmgr_custom_gendir}tls/ca/"
  
  check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/${CLNT1}"
  sc_qmgr_clnt_crtdir="${sc_qmgr_custom_gendir}tls/${CLNT1}/"
  
  check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/qmgr"
  sc_qmgr_srv_crtdir="${sc_qmgr_custom_gendir}tls/qmgr/"
  
  # CCDT tmpl file
  sc_ccdt_tmpl_file="${MY_MQ_SCRIPTDIR}scripts/tmpl/json/ccdt.json";
  MQCCDTURL="${sc_qmgr_custom_gendir}json/ccdt.json"

  trace_out 2 mq_init
}

################################################
# main function
# Main logic
function main() {
  trace_in 3 main

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
        trace_out 3 main
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
              trace_out 3 main
              return 1
            fi;;
    esac

  trace_out 3 main
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
export VAR_MQ_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../config/mq.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}preambule.properties"

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