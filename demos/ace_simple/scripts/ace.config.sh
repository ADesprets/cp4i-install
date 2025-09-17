#!/bin/bash
################################################
# Display information to access CP4I
function ace_display_access_info() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ace_display_access_info

  mylog info "==== Displaying Access Info to CP4I." 0

  local lf_bookmarks_file="${VAR_ACE_WORKINGDIR}ace_simple_bookmarks.html"

  # Initialisation of the bookmark
  echo ${BOOKMARK_PROLOGUE} > ${lf_bookmarks_file}

  # Loop through files in the barfiles directory
  for sc_barfiledir in ${sc_ace_barfiles_dir}*; do
    read_config_file "${sc_barfiledir}/appName.properties"
    sc_ace_barfile_name=$(basename "${sc_barfiledir}")
    sc_ace_barfile_name_lc=$(echo "${sc_ace_barfile_name}" | tr '[:upper:]' '[:lower:]')  
    export VAR_ACE_INTEGRATIONRUNTIME_NAME="${sc_ace_barfile_name_lc}-integrationruntime"
    local lf_app_http_url="http://${VAR_ACE_INTEGRATIONRUNTIME_NAME}-http-${VAR_ACE_NAMESPACE}.apps.${VAR_CLUSTER_DOMAIN}/${VAR_APP_NAME}"
    local lf_app_https_url="https://${VAR_ACE_INTEGRATIONRUNTIME_NAME}-https-${VAR_ACE_NAMESPACE}.apps.${VAR_CLUSTER_DOMAIN}/${VAR_APP_NAME}"
    mylog info "http url for Application ${sc_ace_barfile_name_lc} : $lf_app_http_url" 0
    mylog info "https url for Application ${sc_ace_barfile_name_lc} : $lf_app_https_url" 0
    echo "<DT><A HREF=${lf_app_http_url}>ACE application ${sc_ace_barfile_name_lc} http url</A>" >> ${lf_bookmarks_file}
    echo "<DT><A HREF=${lf_app_https_url}>ACE application ${sc_ace_barfile_name_lc} https url</A>" >> ${lf_bookmarks_file}
  done

  echo ${BOOKMARK_EPILOGUE} >> ${lf_bookmarks_file}

  trace_out $lf_tracelevel ace_display_access_info
}

################################################
# Create secret to be used by barauth type
# this secret will be used to access theserver hosting bar files
################################################
function create_secret_for_barauth () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_secret_for_barauth
 
  local lf_in_json_file=$1
  decho $lf_tracelevel "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument: the file"
    trace_out $lf_tracelevel create_secret_for_barauth
    exit  1
  fi

  # check for the existence of all needed files 
  check_file_exist $lf_in_json_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : secret to be used by barauth type"

  # Check if the secret already exists
  if $MY_CLUSTER_COMMAND get secret ${VAR_ACE_BARAUTH_SECRET_NAME} -n=${VAR_ACE_NAMESPACE} >/dev/null 2>&1; then
    mylog "info" "Secret ${VAR_ACE_BARAUTH_SECRET_NAME} already exists"
  else
    $MY_CLUSTER_COMMAND -n=${VAR_ACE_NAMESPACE} create secret generic ${VAR_ACE_BARAUTH_SECRET_NAME} --from-file=configuration=${lf_in_json_file} 
  fi

  trace_out $lf_tracelevel create_secret_for_barauth
}

################################################
# Create Openshift ACE config type : barauth
################################################
function create_ace_config_barauth () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_ace_config_barauth
 
  local lf_in_file=$1
  decho $lf_tracelevel "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument: the file"
    trace_out $lf_tracelevel create_ace_config_barauth
    exit  1
  fi

  local lf_file_bn=$(basename "${lf_in_file}")
  local lf_gen_file=${sc_generatedyamldir}${lf_file_bn}

  decho $lf_tracelevel "lf_in_file: ${lf_in_file}|lf_gen_file:${lf_gen_file}"

  # check for the existence of all needed files 
  check_file_exist $lf_in_file

  # Generate ace barauth config
  mylog "info" "Creating : ace config barauth"
  cat ${lf_in_file} | envsubst > ${lf_gen_file}

  # Check if the resource already exists
  if $MY_CLUSTER_COMMAND get -n ${VAR_ACE_NAMESPACE} -f ${lf_gen_file} >/dev/null 2>&1; then
    mylog "info" "Resource already exists"
  else
    $MY_CLUSTER_COMMAND -n ${VAR_ACE_NAMESPACE} apply -f ${lf_gen_file}
  fi

  trace_out $lf_tracelevel create_ace_config_barauth
}

################################################
# Create Openshift ACE config type : serverconf
################################################
function create_ace_config_serverconf () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_ace_config_serverconf
 
  local lf_in_file=$1
  decho $lf_tracelevel "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument: the file"
    trace_out $lf_tracelevel create_ace_config_serverconf
    exit  1
  fi

  # Get the basename and filename without extension
  # https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
  local lf_file_bn=$(basename "${lf_in_file}")
  local lf_file_bn_wo_ext="${lf_file_bn%.*}"
  decho $lf_tracelevel "lf_in_file: ${lf_in_file}|lf_file_bn:${lf_file_bn}|lf_file_bn_wo_ext:${lf_file_bn_wo_ext}"

  local lf_yaml_file="${sc_ace_tmpl_yaml_dir}${lf_file_bn_wo_ext}.yaml"
  local lf_gen_file="${sc_generatedyamldir}${lf_file_bn_wo_ext}.yaml"

  # check for the existence of all needed files 
  check_file_exist $lf_in_file
  check_file_exist $lf_yaml_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : ace config serverconf"
  export VAR_ACE_SERVER_CONF_YAML_B64=$(encode_b64_file $lf_in_file)
  cat "${lf_yaml_file}" | envsubst > "${lf_gen_file}" 

  # Apply the generated yaml file
  # Check if the resource already exists
  if $MY_CLUSTER_COMMAND get -n ${VAR_ACE_NAMESPACE} -f ${lf_gen_file} >/dev/null 2>&1; then
    mylog "info" "Resource already exists"
  else
    $MY_CLUSTER_COMMAND -n ${VAR_ACE_NAMESPACE} apply -f ${lf_gen_file}
  fi

  trace_out $lf_tracelevel create_ace_config_serverconf
}

################################################
# run all 
################################################
function ace_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ace_run_all

  # Loop through files in the barfiles directory
  for sc_barfiledir in ${sc_ace_barfiles_dir}*; do
  
    decho $lf_tracelevel "sc_barfiledir: ${sc_barfiledir}"
  
    sc_ace_barfile_name=$(basename "${sc_barfiledir}")
    # We have to use lower cases for secret due to the following rules :
    # error: failed to create secret Secret "HTTPEchoApp-barauth-secret" is invalid: metadata.name: 
    # Invalid value: "HTTPEchoApp-barauth-secret": a lowercase RFC 1123 subdomain must consist of 
    # lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character 
    # (e.g. 'example.com', regex used for validation is '[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*')
    sc_ace_barfile_name_lc=$(echo "${sc_ace_barfile_name}" | tr '[:upper:]' '[:lower:]')
    sc_ace_tmpl_yaml_dir="${sc_barfiledir}/tmpl/"
    sc_ace_configurationtypes_dir="${sc_barfiledir}/configurationtypes/"
  
    export VAR_ACE_BAR_URL="${MY_ACE_REPOSITORY_URL}${sc_ace_barfile_name}.bar"
    export VAR_ACE_BARAUTH_SECRET_NAME="${sc_ace_barfile_name_lc}-barauth-secret"
    export VAR_ACE_SERVERCONF_NAME="${sc_ace_barfile_name_lc}-serverconf"
    export VAR_ACE_BARAUTH_NAME="${sc_ace_barfile_name_lc}-barauth"
    export VAR_ACE_INTEGRATIONRUNTIME_NAME="${sc_ace_barfile_name_lc}-integrationruntime"

    check_directory_exist_create  "${MY_ACE_WORKINGDIR}generated/${sc_ace_barfile_name}"
    sc_ace_custom_gendir="${MY_ACE_WORKINGDIR}generated/${sc_ace_barfile_name}/"
  
    check_directory_exist_create  "${sc_ace_custom_gendir}yaml"
    sc_generatedyamldir="${sc_ace_custom_gendir}yaml/"
  
    # Process all the configuration types before creating the IntegrationRuntime (ex: IntegrationServer)
    for sc_configfile in "${sc_ace_configurationtypes_dir}"*; do
      # Get the file basename then the filename without extension
      sc_configfile_bn=$(basename "${sc_configfile}")
      sc_configtype="${sc_configfile_bn%.*}"
      decho $lf_tracelevel "sc_configfile: ${sc_configfile}|sc_configfile_bn=$sc_configfile_bn|sc_configtype:${sc_configtype}"
  
      decho $lf_tracelevel "sc_configtype: ${sc_configtype}"
      # SB]20240524 Process the different ACE configuration types
      # https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference
      # https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference
      case "${sc_configtype}" in
        "accounts") mylog "info" "policyproject:tbd";;
        "adminssl") mylog "info" "policyproject:tbd";;
        "agenta") mylog "info" "policyproject:tbd";;
        "agentx") mylog "info" "policyproject:tbd";;
        "barauth") create_secret_for_barauth "${sc_ace_configurationtypes_dir}${sc_configfile_bn}"
                   create_ace_config_barauth "${sc_ace_tmpl_yaml_dir}${sc_configtype}.yaml";;
        "db2cli") mylog "info" "policyproject:tbd";;
        "generic") mylog "info" "policyproject:tbd";;
        "keystore") mylog "info" "policyproject:tbd";;
        "loopbackdatasource") mylog "info" "policyproject:tbd";;
        "mqccdt") mylog "info" "policyproject:tbd";;
        "mqccred") mylog "info" "policyproject:tbd";;
        "odbc") mylog "info" "policyproject:tbd";;
        "persistencerediscredentials") mylog "info" "policyproject:tbd";;
        "policyproject") mylog "info" "policyproject:tbd";;
        "privatenetworkagent") mylog "info" "privatenetworkagent:tbd";;
        "resiliencekafkacredentials") mylog "info" "resiliencekafkacredentials:tbd";;
        "s3credentials") mylog "info" "s3credentials:tbd";;
        "serverconf") create_ace_config_serverconf "${sc_ace_configurationtypes_dir}${sc_configfile_bn}";;
        "setdbparms") mylog "info" "setdbparms:tbd";;
        "truststore") mylog "info" "truststore:tbd";;
        "truststorecertificate") mylog "info" "truststorecertificate:tbd";;
        "Vault") mylog "info" "Vault:tbd";;
        "VaultKey") mylog "info" "VaultKey:tbd";;
        "workdiroverride") mylog "info" "workdiroverride:tbd";;
        *) mylog "error" "Unknown configuration type: ${sc_ace_barfile_name}";;
      esac
    done
  
    # Create the IntegrationRuntime (ex: IntegrationServer)
    adapt_file "${sc_ace_tmpl_yaml_dir}" "${sc_generatedyamldir}" "integrationruntime.yaml"
  
    # Check if the resource already exists
    if $MY_CLUSTER_COMMAND get -n ${VAR_ACE_NAMESPACE} -f -f "${sc_generatedyamldir}integrationruntime.yaml" >/dev/null 2>&1; then
      mylog "info" "Resource already exists"
    else
      $MY_CLUSTER_COMMAND -n ${VAR_ACE_NAMESPACE} apply -f "${sc_generatedyamldir}integrationruntime.yaml"
    fi
    
  done

  trace_out $lf_tracelevel ace_run_all
}

################################################
# initialisation
function ace_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ace_init

  export VAR_ACE_WORKINGDIR="${MY_WORKINGDIR}demos/ace_simple/working/"
  check_directory_exist_create "${VAR_ACE_WORKINGDIR}"

  # get the dns name of the cluster
  export VAR_CLUSTER_DOMAIN=$($MY_CLUSTER_COMMAND get dns cluster -o jsonpath='{.spec.baseDomain}')

  create_project "${VAR_ACE_NAMESPACE}" "${VAR_ACE_NAMESPACE} project" "For App Connect" "${MY_RESOURCESDIR}" "${MY_ACE_WORKINGDIR}"
  
  # Data directory (in this case bar files directory)
  sc_ace_barfiles_dir="${sc_component_script_dir}/BarFiles/"
  trace_out $lf_tracelevel ace_init
}

################################################
# main function
# Main logic
function main() {
  local lf_starting_date=$(date)
  local lf_satrting_date_in_seconds=$(date +%s)
  mylog info "==== Simple Demo ACE (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  SECONDS=0
  local lf_starting_date=$(date);
  
  local lf_tracelevel=1
  trace_in $lf_tracelevel main

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    trace_out $lf_tracelevel main
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
        trace_out $lf_tracelevel main
        return 1
        ;;
      esac
  done
  #lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces
  lf_calls=$(echo "$lf_calls" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')

  # Call processing function if --call was used
  case $lf_key in
    --all) ace_run_all "$@";;
    --call) if [[ -n $lf_calls ]]; then
              process_calls "$lf_calls"
            else
              mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
              trace_out $lf_tracelevel main
              return 1
            fi;;
    esac

  trace_out $lf_tracelevel main

  ace_display_access_info

  local lf_ending_date=$(date)
  local lf_ending_date_in_seconds=$(date +%s)
  local lf_duration=$((lf_ending_date_in_seconds - lf_satrting_date_in_seconds))
  mylog info "==== Simple Demo ACE (${FUNCNAME[0]})  [ended : $lf_ending_date and took : $(($lf_duration / 60)) minutes and $(($lf_duration % 60)) seconds]." 0

  exit 0
}

################################################
# Start of the script main entry
################################################
# other example: ./ace.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./ace.config.sh --all
################################################

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

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/ace.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load properties files
. "${sc_provision_constant_properties_file}"

# load properties files
. "${sc_provision_variable_properties_file}"

# Load mq variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

ace_init

trap 'ace_display_access_info' EXIT

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi