#!/bin/bash
################################################
# simple logging with colors
# @param 1 level (info/error/warn/wait/check/ok/no)
function mylog() {
  local lf_spaces=$(printf "%0.s " $(seq 1 $SC_SPACES_COUNTER))

  # prefix
  local p=
  # do not output the trailing newline
  local w=
  # suffix
  local s=
  case $1 in
    info)    c=2;;          #green
    error)   c=1            #red
             p='ERROR: ';;
    warn)    c=3;;          #yellow
    debug)   c=8            #grey
             p='CMD: ';; 
    wait)    c=4            #purple
             p="$(date) ";;
    check)   c=6            #cyan
             w=-n
             s=...;; 
    ok)      c=2            #green
             p=OK;;
    no)      c=3            #yellow
             p=NO;;  
    default) c=9            #default
             p='';;
  esac
  shift
  echo $w "$(tput setaf $c)$lf_spaces$p$@$s$(tput setaf 9)"
}

#########################################################################
# function to print message if debug is set to 1
function decho () {
  local lf_in_messagelevel=$1
  shift 1

  if [ -n "$ADEBUG" ]; then
    if [ $TRACELEVEL -ge $lf_in_messagelevel ]; then
      mylog debug "$@"
    fi
  fi
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
function check_add_cs_ibm_pak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_add_cs_ibm_pak"
  SECONDS=0

  local lf_in_case_name="$1"
  local lf_in_arch="$2"
  local lf_in_case_version="$3"

  local lf_case_version lf_file lf_downloaded

  #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
  if [ -z "$lf_in_case_version" ]; then
    local lf_case_version=$(oc ibm-pak list -o json | jq -r --arg case "$lf_in_case_name" '.[] | select (.name == $case ) | .latestVersion')
  else
    lf_case_version=$lf_in_case_version
  fi
  
  oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}
  oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}

  mylog info "Getting case $lf_in_case_name took $SECONDS seconds to execute." 1>&2

  decho 4 "F:OUT:check_add_cs_ibm_pak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################################################################
# Start of the script main entry
################################################################################################
# @param sc_properties_file: file path and name of the properties file
# @param MY_OC_PROJECT: namespace where to create the operators and capabilities
# @param sc_cluster_name: name of the cluster
# example of invocation: ./provision_cluster-v2.sh private/my-cp4i.properties sbtest cp4i-sb-cluster
# other example: ./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-16.1.0.properties cp4i sb20240102
# other example: ./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-16.1.0.properties cp4i ad202341
#
export ADEBUG=1
export TECHZONE=true
export TRACELEVEL=4

# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=3

MY_COMMONSERVICES_CASE="ibm-cp-common-services"
#MY_COMMONSERVICES_VERSION=4.6.3
MY_COMMONSERVICES_VERSION=4.7.0
MY_WL_CASE="ibm-websphere-liberty"
MY_NAVIGATOR_CASE="ibm-integration-platform-navigator"
MY_ACE_CASE="ibm-appconnect"
MY_APIC_CASE="ibm-apiconnect"
MY_ES_CASE="ibm-eventstreams"
MY_EEM_CASE="ibm-eventendpointmanagement"
MY_FLINK_CASE="ibm-eventautomation-flink"
MY_EP_CASE="ibm-eventprocessing"
MY_HSTS_CASE="ibm-aspera-hsts-operator"
MY_MQ_CASE="ibm-mq"

#check_add_cs_ibm_pak ibm-licensing amd64
check_add_cs_ibm_pak $MY_COMMONSERVICES_CASE amd64 $MY_COMMONSERVICES_VERSION
#check_add_cs_ibm_pak $MY_WL_CASE amd64
#check_add_cs_ibm_pak $MY_NAVIGATOR_CASE amd64
#check_add_cs_ibm_pak ibm-integration-asset-repository amd64
#check_add_cs_ibm_pak $MY_ACE_CASE amd64
#check_add_cs_ibm_pak $MY_APIC_CASE amd64
#check_add_cs_ibm_pak $MY_ES_CASE amd64
#check_add_cs_ibm_pak $MY_EEM_CASE amd64
#check_add_cs_ibm_pak $MY_FLINK_CASE amd64
#check_add_cs_ibm_pak $MY_EP_CASE amd64
#check_add_cs_ibm_pak $MY_HSTS_CASE amd64
#check_add_cs_ibm_pak $MY_MQ_CASE amd64
