#!/bin/bash
################################################################
# Create secret to be used by barauth type
# this secret will be used to access theserver hosting bar files
################################################################
function create_secret_for_barauth () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN :create_secret_for_barauth"
 
  local lf_in_json_file=$1

  # check for the existence of all needed files 
  check_file_exist $lf_in_json_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : secret to be used by barauth type"

  # Check if the secret already exists
  if oc get secret ${MY_ACE_BARAUTH_SECRET_NAME} -n=${MY_OC_PROJECT} >/dev/null 2>&1; then
    mylog "info" "Secret ${MY_ACE_BARAUTH_SECRET_NAME} already exists"
  else
    oc -n=${MY_OC_PROJECT} create secret generic ${MY_ACE_BARAUTH_SECRET_NAME} --from-file=configuration=${lf_in_json_file} 
  fi

  decho 3 "F:OUT:create_secret_for_barauth"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}

################################################
# Create Openshift ACE config type : barauth
#################################################
function create_ace_config_barauth () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN :create_ace_config_barauth"
 
  local lf_in_file=$1
  local lf_file_bn=$(basename "${lf_in_file}")
  local lf_gen_file=${sc_generatedyamldir}${lf_file_bn}

  decho 3 "lf_in_file: ${lf_in_file}|lf_gen_file:${lf_gen_file}"

  # check for the existence of all needed files 
  check_file_exist $lf_in_file

  # Generate ace barauth config
  mylog "info" "Creating : ace config barauth"
  cat ${lf_in_file} | envsubst > ${lf_gen_file}

  # Check if the resource already exists
  if oc get -n ${MY_OC_PROJECT} -f ${lf_gen_file} >/dev/null 2>&1; then
    mylog "info" "Resource already exists"
  else
    oc -n ${MY_OC_PROJECT} apply -f ${lf_gen_file}
  fi

  decho 3 "F:OUT:create_ace_config_barauth"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}

################################################
# Create Openshift ACE config type : serverconf
#################################################
function create_ace_config_serverconf () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN :create_ace_config_serverconf"
 
  local lf_in_file=$1

  # Get the basename and filename without extension
  # https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
  local lf_file_bn=$(basename "${lf_in_file}")
  local lf_file_bn_wo_ext="${lf_file_bn%.*}"
  decho 3 "lf_in_file: ${lf_in_file}|lf_file_bn:${lf_file_bn}|lf_file_bn_wo_ext:${lf_file_bn_wo_ext}"

  local lf_yaml_file="${TMPLYAMLDIR}${lf_file_bn_wo_ext}.yaml"
  local lf_gen_file="${sc_generatedyamldir}${lf_file_bn_wo_ext}.yaml"

  # check for the existence of all needed files 
  check_file_exist $lf_in_file
  check_file_exist $lf_yaml_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : ace config serverconf"
  export MY_ACE_SERVER_CONF_YAML_B64=$(encode_b64_file $lf_in_file)
  cat "${lf_yaml_file}" | envsubst > "${lf_gen_file}" 

  # Apply the generated yaml file
  # Check if the resource already exists
  if oc get -n ${MY_OC_PROJECT} -f ${lf_gen_file} >/dev/null 2>&1; then
    mylog "info" "Resource already exists"
  else
    oc -n ${MY_OC_PROJECT} apply -f ${lf_gen_file}
  fi

  decho 3 "F:OUT:create_ace_config_serverconf"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}

################################################################################################
# Start of the script main entry
# main

starting=$(date);

SECONDS=0

# end with / on purpose
#SCRIPTDIR=$(dirname "$0")/
SCRIPTDIR="${MY_ACE_SCRIPTDIR}scripts/"
CONFIGDIR="${SCRIPTDIR}../config/"

MAINSCRIPTDIR="${SCRIPTDIR}../../../"

# Template directories
BARFILESDIR="${SCRIPTDIR}BarFiles/"

#SB]20240524 Only the following variable is global for all bar files (Check if there others in which case put all them in a config file)
MY_ACE_REPOSITORY_URL="https://raw.githubusercontent.com/saadbenachi/my_bar_files/main/"

# SB]20240404 Global Index sequence for incremental output for each function call
SC_SPACES_COUNTER=0
SC_SPACES_INCR=3

: <<'END_COMMENT'
END_COMMENT

# Loop through files in the barfiles directory
for sc_barfiledir in ${BARFILESDIR}*; do

  decho 3 "sc_barfiledir: ${sc_barfiledir}"

  export MY_ACE_BAR_NAME=$(basename "${sc_barfiledir}")

  # We have to use lower cases for secret due to the following rules :
  # error: failed to create secret Secret "HTTPEchoApp-barauth-secret" is invalid: metadata.name: 
  # Invalid value: "HTTPEchoApp-barauth-secret": a lowercase RFC 1123 subdomain must consist of 
  # lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character 
  # (e.g. 'example.com', regex used for validation is '[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*')

  export MY_ACE_BAR_NAME_LC=$(echo "${MY_ACE_BAR_NAME}" | tr '[:upper:]' '[:lower:]')
  TMPLYAMLDIR="${sc_barfiledir}/tmpl/"
  CONFIGURATIONTYPESDIR="${sc_barfiledir}/configurationtypes/"

  # load config file here in the loop because it depends on the name of the bar file
  read_config_file "${CONFIGDIR}ace.properties"

  check_directory_exist_create  "${MY_ACE_GEN_CUSTOMDIR}generated/${MY_ACE_BAR_NAME}"
  sc_generateddir="${MY_ACE_GEN_CUSTOMDIR}generated/${MY_ACE_BAR_NAME}/"

  check_directory_exist_create  "${sc_generateddir}yaml"
  sc_generatedyamldir="${sc_generateddir}yaml/"

  # Process all the configuration types before creating the IntegrationRuntime (ex: IntegrationServer)
  for sc_configfile in "${CONFIGURATIONTYPESDIR}"*; do
    # Get the file basename then the filename without extension
    sc_configfile_bn=$(basename "${sc_configfile}")
    sc_configtype="${sc_configfile_bn%.*}"
    decho 3 "sc_configfile: ${sc_configfile}|sc_configfile_bn=$sc_configfile_bn|sc_configtype:${sc_configtype}"

    decho 3 "sc_configtype: ${sc_configtype}"
    # SB]20240524 Process the different ACE configuration types
    # https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference
    # https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference
    case "${sc_configtype}" in
      "accounts") mylog "info" "policyproject:tbd";;
      "adminssl") mylog "info" "policyproject:tbd";;
      "agenta") mylog "info" "policyproject:tbd";;
      "agentx") mylog "info" "policyproject:tbd";;
      "barauth") create_secret_for_barauth "${CONFIGURATIONTYPESDIR}${sc_configfile_bn}"
                 create_ace_config_barauth "${TMPLYAMLDIR}${sc_configtype}.yaml";;
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
      "serverconf") create_ace_config_serverconf "${CONFIGURATIONTYPESDIR}${sc_configfile_bn}";;
      "setdbparms") mylog "info" "setdbparms:tbd";;
      "truststore") mylog "info" "truststore:tbd";;
      "truststorecertificate") mylog "info" "truststorecertificate:tbd";;
      "Vault") mylog "info" "Vault:tbd";;
      "VaultKey") mylog "info" "VaultKey:tbd";;
      "workdiroverride") mylog "info" "workdiroverride:tbd";;
      *) mylog "error" "Unknown configuration type: ${MY_ACE_BAR_NAME}";;
    esac
  done

  # Create the IntegrationRuntime (ex: IntegrationServer)
  cat "${TMPLYAMLDIR}integrationruntime.yaml" | envsubst > "${sc_generatedyamldir}integrationruntime.yaml"

  # Check if the resource already exists
  if oc get -n ${MY_OC_PROJECT} -f -f "${sc_generatedyamldir}integrationruntime.yaml" >/dev/null 2>&1; then
    mylog "info" "Resource already exists"
  else
    oc -n ${MY_OC_PROJECT} apply -f "${sc_generatedyamldir}integrationruntime.yaml"
  fi

done

duration=$SECONDS
mylog info "Creation of the ACE artefacts took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2