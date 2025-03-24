#############################################################
# Run this script
#############################################################
function run_all () {
  trace_in 3 run_all

  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Creation of certificate chain." 0

  local lf_namespace lf_issuername lf_root_cert_name lf_tls_label1 lf_tls_certname
  
  # Create the certificates/secrets required for MQ Configuration
  lf_namespace=cp4i-mq
  lf_issuername=mq
  lf_root_cert_name=mq
  lf_tls_label1=mq-demo
  # For TLS Certificate, name needs to be lower cases
  lf_tls_certname=qm1
  
  create_certificate_chain $lf_namespace $lf_issuername $lf_root_cert_name $lf_tls_label1 $lf_tls_certname

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
    
  mylog info "==== Creation of certificate chain [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  trace_out 3 run_all
}

################################################
# initialisation
function tls_init() {
  trace_in 2 tls_init

  trace_out 2 tls_init
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
    --all) tls_run_all "$@";;
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
# other example: ./tls.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./tls.config.sh --all
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
export VAR_TLS_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../config/tls.properties"
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

tls_init

######################################################
# main entry
######################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi