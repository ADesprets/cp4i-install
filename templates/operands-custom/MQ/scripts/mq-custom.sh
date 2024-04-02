    # end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

MY_MQ_LIC=

#assumptions on the name od the file
read_config_file "${scriptdir}cp4i.properties"

if [ ! -d ${MQ_GEN_CUSTOMDIR}config ]; then
    mkdir -p ${MQ_GEN_CUSTOMDIR}config
fi
if [ ! -d ${MQ_GEN_CUSTOMDIR}script ]; then
    mkdir -p ${MQ_GEN_CUSTOMDIR}scripts
fi

generate_files $MQ_TMPL_CUSTOMDIR $MQ_GEN_CUSTOMDIR false
#read_config_file "${MQ_GEN_CUSTOMDIR}scripts/ace.properties"
read_config_file "${MQ_GEN_CUSTOMDIR}scripts/mq.properties"

create_namespace $MY_MQ_PROJECT
add_ibm_entitlement $MY_MQ_PROJECT
# generate the differents properties files
# SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
# - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
# - generate first the *.properties files to be sourced then generate the *.yaml files
if [ ! -d ${MQ_GEN_CUSTOMDIR}scripts ]; then
    mkdir -p ${MQ_GEN_CUSTOMDIR}scripts
fi
if [ ! -d ${MQ_GEN_CUSTOMDIR}config ]; then
    mkdir -p ${MQ_GEN_CUSTOMDIR}config
fi
generate_files $MQ_TMPL_CUSTOMDIR $MQ_GEN_CUSTOMDIR false

export mq_availability_type="NativeHA"
export mq_qmgr_name="mainmqm"

mylog info "creating config map with MQSC commands"
lf_mq_ns=$MY_MQ_PROJECT
lf_type="ConfigMap"
lf_cr_name=$mq_qmgr_name-mqsc
lf_yaml_file="${MQ_GEN_CUSTOMDIR}config/$mq_qmgr_name-cm.yaml"

check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_mq_ns}"



lf_file="${MQ_GEN_CUSTOMDIR}config/MQ-Capability.yaml"
lf_ns="${MY_MQ_PROJECT}"
lf_path="{.status.phase}"
lf_resource="$MY_MQ_INSTANCE_NAME"
lf_state="Running"
lf_type="QueueManager"
lf_wait_for_state=0
create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
