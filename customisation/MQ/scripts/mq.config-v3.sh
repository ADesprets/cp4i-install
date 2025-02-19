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

  local lf_calls="$1"  # Get the full string of calls and parameters
  local lf_commands    # Array to store the commands
  local lf_cmd         # Command to process
  local lf_func        # Function name
  local lf_params      # Parameters
  local lf_list        # List of available functions


    # Split the calls by comma and loop through each
    IFS=',' read -ra lf_commands <<< "$lf_calls"
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
        #install_needed_resources_part
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

sc_script_dir="$( cd "$( dirname "$0" )" && pwd )/"

export ADEBUG=1
export TECHZONE=true
export TRACELEVEL=6
# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=2
export SC_SPACES_INCR_INSIDE_FUNCTION=2

MAINSCRIPTDIR="${sc_script_dir}../../../"
sc_properties_file="${MAINSCRIPTDIR}properties/cp4i.properties"
sc_lib_file="${MAINSCRIPTDIR}lib.sh"
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

######################################################
# main entry
######################################################
main "$@"