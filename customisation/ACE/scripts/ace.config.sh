#!/bin/bash
################################################################
# Create secret to be used by barauth type
# this secret will be used to access theserver hosting bar files
################################################################
function create_secret_for_barauth () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_secret_for_barauth"
 
  local lf_in_json_file=$1

  # check for the existence of all needed files 
  check_file_exist $lf_in_json_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : secret to be used by barauth type"

  oc create secret generic ${MY_ACE_BARAUTH_SECRET_NAME} --from-file=configuration=${lf_in_json_file} -n=${MY_OC_PROJECT}

  decho "F:OUT:create_secret_for_barauth"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}


################################################
# Create Openshift ACE config type : serverconf
#################################################
function create_ace_config_serverconf () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_ace_config_serverconf"
 
  local lf_in_resource_file=$1
  local lf_in_tmpl_file=$2
  
  local lf_gen_file=${sc_generatedyamldir}${lf_in_tmpl_file}

  # check for the existence of all needed files 
  check_file_exist $lf_in_resource_file
  check_file_exist $lf_in_tmpl_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : ace config serverconf"
  export MY_ACE_SERVER_CONF_YAML_B64=$(encode_b64_file $lf_in_resource_file)
  cat ${lf_in_tmpl_file} | envsubst > ${lf_gen_file} 

  decho "F:OUT:create_ace_config_serverconf"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}

################################################
# Create Openshift ACE config type : barauth
#################################################
function create_ace_config_barauth () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_ace_config_barauth"
 
  local lf_in_tmpl_file=$1
  local lf_gen_file=${sc_generatedyamldir}${lf_in_tmpl_file}

  # check for the existence of all needed files 
  check_file_exist $lf_in_tmpl_file


  # Generate ace barauth config
  mylog "info" "Creating   : ace config barauth"
  cat ${lf_in_tmpl_file} | envsubst > ${lf_gen_file}

  decho "F:OUT:create_ace_config_barauth"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}

################################################
# Configure ACE IS
function configure_ace_is() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :configure_ace_is"

  local ns=$1
  ace_bar_secret=${MY_ACE_BARAUTH_secret}-${my_global_index}
  ace_bar_auth=${MY_ACE_BARAUTH}-${my_global_index}
  ace_is=${MY_ACE_IS}-${my_global_index}

  # Create secret for barauth
  # Reference : https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference#install__install_cli

  #export MY_ACE_BARAUTH_secret_b64=`base64 -w 0 ${ACE_CONFIGDIR}ACE-basic-auth.json`
  if oc -n=$ns get secret $ace_bar_secret >/dev/null 2>&1; then mylog ok; else
    oc -n=$ns create secret generic $ace_bar_secret --from-file=configuration="${ACE_CONFIGDIR}ACE-basic-auth.json"
  fi

  # Create a barauth
  lf_type="Configuration"
  lf_cr_name=$ace_bar_auth
  lf_yaml_file="${ACE_CONFIGDIR}ACE-barauth-${my_global_index}.yaml"
  lf_namespace=$ns
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

  # Create an IS
  lf_type="IntegrationServer"
  lf_cr_name=$ace_is
  lf_yaml_file="${ACE_CONFIGDIR}ACE-IS-${my_global_index}.yaml"
  lf_namespace=$ns
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  wait_for_state IntegrationServer "$ace_is" Ready '{.status.phase}' $ns

  decho "F:OUT:configure_ace_is"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}


################################################################################################
# Start of the script main entry
# main

starting=$(date);

# Creation d'un Queue Manager
SECONDS=0

# end with / on purpose
#SCRIPTDIR=$(dirname "$0")/
SCRIPTDIR="${ACE_SCRIPTDIR}scripts/"
CONFIGDIR="${SCRIPTDIR}../config/"

MAINSCRIPTDIR="${SCRIPTDIR}../../../"

# Template directories
TMPLJSONDIR="${SCRIPTDIR}tmpl/json/"
TMPLYAMLDIR="${SCRIPTDIR}tmpl/yaml/"
TMPLTLSDIR="${SCRIPTDIR}tmpl/tls/"
RESOURCESDIR="${SCRIPTDIR}resources/"


# SB]20240404 Global Index sequence for incremental output for each function call
SC_SPACES_COUNTER=0
SC_SPACES_INCR=3

# load config file
read_config_file "${CONFIGDIR}ace.properties"

check_directory_exist_create  "${SCRIPTDIR}generated/"
sc_generateddir="${SCRIPTDIR}generated/"

check_directory_exist_create  "${sc_generateddir}yaml"
sc_generatedyamldir="${sc_generateddir}yaml/"

: <<'END_COMMENT'
END_COMMENT

# Create PKI resources for qmgr and client
create_secret_for_barauth "${RESOURCESDIR}ace-barauth.json"

# Create openshift resources for qmgr (secrets, cm, qmgr, route, ....)
create_oc_qmgr

# Create CCDT file
create_ccdt

#check_create_oc_yaml "QueueManager" "QM1" "${configdir}QM1.yaml" $mq_project
#check_resource_availability "QueueManager" "${mq_instance_name}-qm1" $mq_project
#wait_for_state QueueManager "${mq_instance_name}-qm1" "Running" '.status.phase' $mq_project

duration=$SECONDS
mylog info "Creation of the Queue Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2