#!/bin/bash
################################################################
# Create secret to be used by barauth type
# this secret will be used to access theserver hosting bar files
################################################################
function create_secret_for_barauth () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_secret_for_barauth"
 
  lf_json_file=$1

  # check for the existence of all needed files 
  check_file_exist $lf_json_file

  # Generate server.conf.yaml file
  mylog "info" "Creating   : secret to be used by barauth type"

  oc create secret generic ${MY_ACE_BARAUTH_SECRET_NAME} --from-file=configuration=${lf_json_file} -n=${MY_OC_PROJECT}

  decho "F:OUT:create_secret_for_barauth"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}


################################################
# Create Openshift ACE config type : serverconf
#################################################
function create_ace_config_serverconf () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_ace_config_serverconf"
 
  lf_tmpl_file=$1
  lf_gen_file=$2

  # check for the existence of all needed files 
  check_file_exist $lf_tmpl_file


  # Generate server.conf.yaml file
  mylog "info" "Creating   : ace config serverconf"

  cat ${lf_tmpl_file} | envsubst > ${lf_gen_file}

  decho "F:OUT:create_ace_config_serverconf"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
}

################################################
# Create Openshift ACE config type : barauth
#################################################
function create_ace_config_barauth () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN :create_ace_config_barauth"
 
  lf_tmpl_file=$1
  lf_gen_file=$2

  # check for the existence of all needed files 
  check_file_exist $lf_tmpl_file


  # Generate ace barauth config
  mylog "info" "Creating   : ace config barauth"
  cat ${lf_tmpl_file} | envsubst > ${lf_gen_file}

  decho "F:OUT:create_ace_config_barauth"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))    
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
create_secret_for_barauth "${RESOURCESDIR}barauth.json"

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