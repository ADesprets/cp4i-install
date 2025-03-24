#############################################################
# Run this script
#############################################################
function ldap_run_all () {
  trace_in 2 ldap_run_all

  SECONDS=0
  local lf_starting_date=$(date);
  
  # launch custom script
  mylog info "Customise ldap (ldap.config.sh)." 0

  # load users and groups into LDAP
  load_users_2_ldap_server "${VAR_LDAP_TMPL_DIRECTORY}" "${VAR_LDAP_WORKINGDIR}" "${VAR_LDAP_LDIF_FILE}"
  
  local lf_ending_date=$(date)
    
  mylog info "==== Customisation of ldap [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  trace_out 2 ldap_run_all
}

################################################
# initialisation
function ldap_init() {
  trace_in 1 ldap_init

  read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
  export VAR_LDAP_PORT=$(oc -n ${VAR_LDAP_NAMESPACE} get service "${VAR_LDAP_SERVICE}" -o jsonpath='{.spec.ports[0].nodePort}')
  export VAR_LDAP_HOSTNAME=$(oc -n ${VAR_LDAP_NAMESPACE} get route "${VAR_LDAP_ROUTE}" -o jsonpath='{.spec.host}')

  trace_out 1 ldap_init
}

################################################
# main function
# Main logic
function main() {
  trace_in 1 main

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    trace_out 1 main
    exit 1
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
    --all) ldap_run_all "$@";;
    --call) if [[ -n $lf_calls ]]; then
              process_calls "$lf_calls"
            else
              mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
              trace_out 3 main
              return 1
            fi;;
    esac

  trace_out 1 main
  exit 0
}

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./ldap.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./ldap.config.sh --all
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
export VAR_LDAP_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}preambule.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../config/ldap.properties"

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

ldap_init

######################################################
# main entry
######################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi