#!/bin/bash
#####################################################################################################################
# Script using cert manager
#####################################################################################################################


#############################################################
function create_issuer () {
  trace_in 3 create_issuer

  local lf_type="Issuer"
  local lf_cr_name="${QMGR}-issuer"
  local lf_source_directory="$MY_RESOURCESDIR"
  local lf_target_directory="$MY_MQ_WORKINGDIR"
  local lf_yaml_file="self-signed-issuer.yaml"
  local lf_namespace=$MY_OC_PROJECT
  export MY_ISSUER=$lf_cr_name
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
  unset MY_ISSUER

   trace_out 3 create_issuer
}

#############################################################
function create_qmgr_certificate () {
  trace_in 3 create_qmgr_certificate

  local lf_type="Certificate"
  local lf_cr_name="${QMGR}-root-cert"
  local lf_source_directory="$sc_mq_tmpl_yaml_dir"
  local lf_target_directory="$MY_MQ_WORKINGDIR"
  local lf_yaml_file="qmgr_CACertificate-v3.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  trace_out 3 create_qmgr_certificate
}

#############################################################
function create_qmgr_configmap () {
  trace_in 3 create_qmgr_configmap

  local lf_type="ConfigMap"
  local lf_cr_name="${QMGR}-mqsc-cm"
  local lf_source_directory="$sc_mq_tmpl_yaml_dir"
  local lf_target_directory="$MY_MQ_WORKINGDIR"
  local lf_yaml_file="qmgr_configmap-v3.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  trace_out 3 create_qmgr_configmap
}

#############################################################
function create_qmgr_route () {
  trace_in 3 create_qmgr_route

  local lf_type="Route"
  local lf_cr_name="${QMGR}-route"
  local lf_source_directory="$sc_mq_tmpl_yaml_dir"
  local lf_target_directory="$MY_MQ_WORKINGDIR"
  local lf_yaml_file="qmgr_route-v3.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  trace_out 3 create_qmgr_route
}

#############################################################
function create_qmgr () {
  trace_in 3 create_qmgr

  local lf_type="QueueManager"
  local lf_cr_name="${QMGR}"
  local lf_source_directory="$sc_mq_tmpl_yaml_dir"
  local lf_target_directory="$MY_MQ_WORKINGDIR"
  local lf_yaml_file="qmgr-v3.yaml"
  local lf_namespace=$MY_OC_PROJECT
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

  local lf_state="Running"
  local lf_path="{.status.phase}"
  decho 3 "wait_for_state \"$lf_type $lf_cr_name $lf_path is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath=$lf_path\""
  wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath=$lf_path"
  
  trace_out 3 create_qmgr
}

#################################################
# Create client key repository
#################################################
function create_clnt_kdb () {
  trace_in 3 create_clnt_kdb

  mylog "info" "Creating   : client key database for $sc_clnt to use with MQSSLKEYR env variable."

  case $KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${sc_qmgr_clnt_crtdir}${sc_clnt}-keystore.p12";;
  esac  

  # Create the client1 key database:
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $KEYDB_TYPE -stash > /dev/null 2>&1  

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
  mylog "info" "Creating   : client key database for $sc_clnt to use with MQSSLKEYR env variable."
  create_clnt_kdb
  
  ##-- Add the queue manager's certificate to the client key database:
  mylog "info" "Adding     : qmgr certificate to the client key database"
  add_qmgr_crt_2_clnt_kdb
  
  ##-- Add CA crt to client kdb
  mylog "info" "Adding     : ca certificate to client kdb for $sc_clnt"
  add_ca_crt_2_clnt_kdb

  trace_out 3 create_pki_cr
}

################################################
# Add qmgr certs to client keydb
#################################################
function add_qmgr_crt_2_clnt_kdb () {
  trace_in 3 add_qmgr_crt_2_clnt_kdb

  mylog "info" "Adding     : qmgr certificate to the client key database"

  save_certificate $MY_OC_PROJECT ${QMGR}-secret tls.crt ${sc_qmgr_srv_crtdir}
  
  local lf_srv_crt="${sc_qmgr_srv_crtdir}${QMGR}-secret.tls.crt.pem"

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

  trace_out 3 add_qmgr_crt_2_clnt_kdb
}

################################################
# Add ca cert to client keydb
#################################################
function add_ca_crt_2_clnt_kdb () {
  trace_in 3 add_ca_crt_2_clnt_kdb

  save_certificate $MY_OC_PROJECT ${QMGR}-secret ca.crt ${sc_qmgr_ca_crtdir}
  
  local lf_ca_crt="${sc_qmgr_srv_crtdir}${QMGR}-secret.ca.crt.pem"

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

  trace_out 3 add_ca_crt_2_clnt_kdb
}

################################################
# Create Openshift CCDT file
################################################
function create_ccdt () {
  trace_in 3 create_ccdt
 
  # check for the existence of all needed files 

  # Generate ccdt file
  mylog "info" "Creating   : ccdt file to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  export ROOTURL=$(oc get route -n $MY_OC_PROJECT "${QMGR}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  decho 3 "ROOTURL=$ROOTURL"

  check_file_exist $sc_ccdt_tmpl_file
  cat ${sc_ccdt_tmpl_file} | envsubst > ${MQCCDTURL}

  trace_out 3 create_ccdt
}


#############################################################
# Run this script natively (from terminal) 
#############################################################
function run_natively () {
  trace_in 3 run_natively

  starting=$(date);
  SECONDS=0

  # I have to get first the qmgr name because it's used in the following configfile
  # SB]20240528: (pour les besoins de test AD) TODO Enhance the variabilisation of the name of the QM
  export QMGR=$(echo "${MY_MQ_INSTANCE_NAME}"| tr '[:upper:]' '[:lower:]')
  export QMGR_UC=$(echo $QMGR | tr '[:lower:]' '[:upper:]')
  export CLNT1="${sc_clnt}"
  
  # Create Issuer
  create_issuer

  # Create qmgr certificate
  create_qmgr_certificate

  # Create qmgr configmap
  create_qmgr_configmap

  # Create qmgr route
  create_qmgr_route

  # Create qmgr
  create_qmgr

  # Create tls artifacts
  create_pki_cr

  duration=$SECONDS
  mylog info "Creation of the Queue Manager took $duration seconds to execute." 1>&2
  
  ending=$(date);
  # echo "------------------------------------"
  mylog info "Start: $starting - end: $ending" 1>&2
  mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2
  trace_out 3 run_natively
}

################################################
# Function to process calls
function process_calls() {
  trace_in 3 process_calls

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
      lf_cmd=$(echo "$lf_cmd" | xargs)

      # Extract the function name and parameters
      lf_func=$(echo "$lf_cmd" | awk '{print $1}')
      lf_params=$(echo "$lf_cmd" | awk '{$1=""; sub(/^ /, ""); print}')  # Get all the parameters after the function name
      decho 3 "Function: $lf_func|Parameters: $lf_params"

      # Check if the function exists and call it
      if declare -f "$lf_func" > /dev/null; then
        if [ "$lf_func" = "main" ] || [ "$lf_func" = "process_calls" ]; then
          mylog error "Functions 'main', 'process_calls' cannot be called."
          trace_out 3 process_calls
          return 1
        fi
        install_needed_resources_part
        $lf_func $lf_params
      else
        mylog error "Function '$lf_func' not found."
        lf_list=$(grep -E '^\s*(function\s+\w+|\w+\s*\(\))' $(basename "$0") | sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\2/')
        mylog info "Available functions are:"
        mylog info "$lf_list"
        trace_out 3 process_calls
        return 1
      fi
    done

  trace_out 3 process_calls
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
        run_natively
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
  if [[ $lf_key == "--call" ]]; then
    if [[ -n $lf_calls ]]; then
      process_calls "$lf_calls"
    else
      mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
      trace_out 3 main
      return 1
    fi
  fi

  trace_out 3 main
  exit 0
}

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./mq.config-v3.sh --call <function_name1>, <function_name2>, ...
# other example: ./mq.config-v3.sh --all
################################################################################################

# SB] getting the path of this script independently from using it directly or calling it from another script
# sc_script_dir="$( cd "$( dirname "$0" )" && pwd )/": this statement returns the calling script path

# the following script returns the absolute path of this script independently from using it directly or calling it from another script
sc_script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"

export ADEBUG=1
export TECHZONE=true
export TRACELEVEL=6
# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=2
export SC_SPACES_INCR_INSIDE_FUNCTION=2

PROVISION_SCRIPTDIR="${sc_script_dir}../../../"
sc_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i.properties"
sc_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_mq_properties_file="${sc_script_dir}../config/mq.properties"
# Template directories
sc_mq_tmpl_json_dir="${sc_script_dir}tmpl/json/"
sc_mq_tmpl_sh_dir="${sc_script_dir}tmpl/sh/"
sc_mq_tmpl_yaml_dir="${sc_script_dir}tmpl/yaml/"
# parameters
sc_clnt="clnt1"

# load helper functions
. ${sc_lib_file}

# load config files
read_config_file "${sc_properties_file}"
read_config_file "${sc_mq_properties_file}"
  
# files containing the list of  executed commands
sc_install_executed_commands_file="${MY_MQ_WORKINGDIR}install_executed_commands.sh"
sc_uninstall_executed_commands_file="${MY_MQ_WORKINGDIR}uninstall_executed_commands.sh"
cat /dev/null > $sc_install_executed_commands_file
cat /dev/null > $sc_uninstall_executed_commands_file

check_directory_exist_create  "${MY_MQ_GEN_CUSTOMDIR}generated/${QMGR}"
sc_qmgr_custom_gendir="${MY_MQ_GEN_CUSTOMDIR}generated/${QMGR}/"

check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/ca"
sc_qmgr_ca_crtdir="${sc_qmgr_custom_gendir}tls/ca/"

check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/${sc_clnt}"
sc_qmgr_clnt_crtdir="${sc_qmgr_custom_gendir}tls/${sc_clnt}/"

check_directory_exist_create  "${sc_qmgr_custom_gendir}tls/qmgr"
sc_qmgr_srv_crtdir="${sc_qmgr_custom_gendir}tls/qmgr/"

# CCDT tmpl file
sc_ccdt_tmpl_file="${MY_MQ_SCRIPTDIR}scripts/tmpl/json/ccdt_tmpl.json";
MQCCDTURL="${sc_qmgr_custom_gendir}json/ccdt.json"
######################################################
# main entry
######################################################
main "$@"