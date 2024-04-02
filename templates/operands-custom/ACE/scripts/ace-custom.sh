# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

#assumptions on the name od the file
read_config_file "${scriptdir}cp4i.properties"

if [ ! -d ${ACE_GEN_CUSTOMDIR}config ]; then
    mkdir -p ${ACE_GEN_CUSTOMDIR}config
fi
if [ ! -d ${ACE_GEN_CUSTOMDIR}script ]; then
    mkdir -p ${ACE_GEN_CUSTOMDIR}scripts
fi

generate_files $ACE_TMPL_CUSTOMDIR $ACE_GEN_CUSTOMDIR false
read_config_file "${ACE_GEN_CUSTOMDIR}scripts/ace.properties"

#!/bin/sh
mylog info "Building BAR Auth Configuration"
###################
# INPUT VARIABLES #
###################
CONFIG_NAME="github-barauth"
CONFIG_TYPE="barauth"
CONFIG_NS="$MY_ACE_PROJECT"
CONFIG_DESCRIPTION="Authentication for GitHub"
CONFIG_DATA_BASE64=$(base64 -i ${ACE_GEN_CUSTOMDIR}config/template-ace-barauth-data.json)
########################
# CREATE CONFIGURATION #
########################
( echo "cat <<EOF" ; cat ${ACE_GEN_CUSTOMDIR}config/template-ace-config-data.yaml ;) | \
    CONFIG_NAME=${CONFIG_NAME} \
    CONFIG_TYPE=${CONFIG_TYPE} \
    CONFIG_NS=${CONFIG_NS} \
    CONFIG_DESCRIPTION=${CONFIG_DESCRIPTION} \
    CONFIG_DATA_BASE64=${CONFIG_DATA_BASE64} \
    sh > ${ACE_GEN_CUSTOMDIR}scripts/ace-config-barauth.yaml
mylog info "Creating ACE Configuration..."

lf_ace_ns=$MY_ACE_PROJECT

lf_type="Configuration"
lf_cr_name=$CONFIG_NAME
lf_yaml_file="${ACE_GEN_CUSTOMDIR}scripts/ace-config-barauth.yaml"

  
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"

#Deploy backend

lf_type="IntegrationRuntime"
lf_cr_name="ace-paym-api-backend"
lf_yaml_file="${ACE_GEN_CUSTOMDIR}config/ace-is-paym-backend.yaml"
  
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"

