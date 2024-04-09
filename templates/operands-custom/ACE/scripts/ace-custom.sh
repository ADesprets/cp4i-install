#########################################################################
# function to print message if debug is set to 1
create_ace_configuration() {
    local lf_config_name=$1
    local lf_config_type=$2
    # type: policyproject, barauth, setdbparms, keystore, truststore .... 
    local lf_config_description=$3
    local lf_config_file_data=$4
    local lf_config_ns=$5

    lf_config_template_file=""
    case $lf_config_type in
        "barauth" | "setdbparms")
            mylog info "process config data"
            lf_config_template_file=${ACE_GEN_CUSTOMDIR}config/template-ace-config-data.yaml
            ;;
        "policyproject" | "keystore")
            mylog info "process config data"
            lf_config_template_file=${ACE_GEN_CUSTOMDIR}config/template-ace-config-content.yaml
            ;;       
        *)
            mylog error "configuration type not recognized: $lf_config_type"
            exit 1
            ;;
    esac

    lf_content_64=$(base64 -i $lf_config_file_data)

    ( echo "cat <<EOF" ; cat ${lf_config_template_file} ;) | \
    CONFIG_NAME="$lf_config_name"\
    CONFIG_TYPE="$lf_config_type" \
    CONFIG_NS="${lf_config_ns}" \
    CONFIG_DESCRIPTION="$lf_config_description" \
    CONFIG_CONTENT_BASE64=${lf_content_64} \
    sh > ${ACE_GEN_CUSTOMDIR}scripts/${lf_config_name}.yaml

    lf_type="Configuration"
    lf_cr_name="$lf_config_name"
    lf_yaml_file="${ACE_GEN_CUSTOMDIR}scripts/${lf_config_name}.yaml"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_config_ns}"
}

create_ace_policy() {
    local lf_policy_project=$1
    local lf_policy_name=$2
    local lf_config_name=$3
    local lf_config_type=$4
    # type: policyproject, barauth, setdbparms, keystore, truststore .... 
    local lf_config_description=$5
    local lf_config_ns=$6

    if [ ! -d ${lf_policy_project} ]; then
        mkdir -p ${lf_policy_project}
    fi
    cat ${ACE_GEN_CUSTOMDIR}config/${lf_policy_name}.policyxml | envsubst > ${lf_policy_project}/${lf_policy_name}.policyxml
    cp ${ACE_GEN_CUSTOMDIR}config/policy.descriptor ${lf_policy_project}/policy.descriptor
    zip -r ${lf_policy_project}.zip ${lf_policy_project}
    rm -R ${lf_policy_project}
    # CONFIG_CONTENT_BASE64=$(base64 -i ${SCRIPTDIR}${lf_policy_name}.zip)
    #rm ${lf_policy_name}.zip
    mv ${lf_policy_project}.zip ${ACE_GEN_CUSTOMDIR}scripts

    create_ace_configuration $lf_policy_name $lf_config_name $lf_config_type $lf_config_description "${ACE_GEN_CUSTOMDIR}scripts/${lf_policy_project}.zip" $lf_config_ns
}



# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
export SCRIPTDIR=${PWD}/

# load helper functions
. "${SCRIPTDIR}"lib.sh

#assumptions on the name od the file
read_config_file "${SCRIPTDIR}cp4i.properties"

if [ ! -d ${ACE_GEN_CUSTOMDIR}config ]; then
    mkdir -p ${ACE_GEN_CUSTOMDIR}config
fi
if [ ! -d ${ACE_GEN_CUSTOMDIR}scripts ]; then
    mkdir -p ${ACE_GEN_CUSTOMDIR}scripts
fi

generate_files $ACE_TMPL_CUSTOMDIR $ACE_GEN_CUSTOMDIR false
read_config_file "${ACE_GEN_CUSTOMDIR}scripts/ace.properties"


: '
mylog info "Deploying ACE Payment Backend API"

mylog info "Building BAR Auth Configuration"

create_ace_configuration "github-barauth" "barauth" "Authentication for GitHub" "${ACE_GEN_CUSTOMDIR}config/template-ace-barauth-data.json" "$MY_ACE_PROJECT" 
# DEPLOY IntegrationRuntime
lf_type="IntegrationRuntime"
lf_cr_name="ace-paym-api-backend"
lf_yaml_file="${ACE_GEN_CUSTOMDIR}config/ace-is-paym-backend.yaml"
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"


mylog info "Deploying ACE MQ Payment"
lf_policy_desc="Policy to connect to ${lf_qmgr_name} Queue Manager"
export QMGR_NAME="mainmqm"
create_ace_policy "pol_cp4i_mq" "pol_cp4i_mq" "ace-policy-qm-mainmqm" "policyproject" "$lf_policy_desc" "$MY_ACE_PROJECT" 
# DEPLOY IntegrationRuntime
lf_type="IntegrationRuntime"
lf_cr_name="ace-paym-proc-api"
lf_yaml_file="${ACE_GEN_CUSTOMDIR}config/ace-ir-paym-proc-api.yaml"
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"

'

# DEPLOY EVENT2MAIL

#Kafka configuration
export KAFKA_BOOTSTRAP_URL="es-demo-kafka-bootstrap:443"
# export KAFKA_BOOTSTRAP_URL=$(oc get eventstreams ${MY_ES_INSTANCE_NAME} -n ${MY_ES_PROJECT} -o=jsonpath='{range .status.kafkaListeners[*]}{.type} {.bootstrapServers}{"\n"}{end}' | awk '$1=="external" {print $2}')
# oc get route -n event es-demo-kafka-bootstrap -ojsonpath='https://{.spec.host}'
export AUTH_SECID="evs-scram"
export TRUSTSTORE="/home/aceuser/truststores/es-cert.p12"
export TRUSTSTORE_TYPE="PKCS12"
export TRUSTSTORE_SECID="truststorePass"

lf_policy_desc="Policy to connect to EventStreams demo"
create_ace_policy "pol_cp4i_kafka" "kafka_cp4i" "ace-policy-kafka-demo" "policyproject" "$lf_policy_desc" "$MY_ACE_PROJECT" 

#TODO how to update a policy

#oc get secret ${ES_INST_NAME}-cluster-ca-cert -n ${ES_NAMESPACE} -o jsonpath="{.data.ca\.crt}" | base64 -D > ${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-ca.pem

#oc get secret ${ES_INST_NAME}-cluster-ca-cert -n ${ES_NAMESPACE} -o jsonpath="{.data.ca\.p12}" | base64 -D > ${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-ca.pem


#!/bin/sh



: '
oc get secret -n ibm-common-services integration-admin-initial-temporary-credentials -o jsonpath='{.data.password}' | base64 -d
# configyration type: truststore
#TRUSTSTORE
ES_INST_NAME='es-demo'
ES_NAMESPACE='tools'
CONFIG_NAME="es-cert.jks"
CONFIG_TYPE="truststore"
CONFIG_DESCRIPTION="JKS certificate for Event Streams instance es-demo"
CONFIG_NS="tools"
oc extract secret/${ES_INST_NAME}-cluster-ca-cert -n ${ES_NAMESPACE} --keys=ca.password
oc extract secret/${ES_INST_NAME}-cluster-ca-cert -n ${ES_NAMESPACE} --keys=ca.password
oc get secret -n event es-all-access -o jsonpath='{.data.password}' | base64 -d
TRUSTSTORE_PWD=`cat ca.password`

oc extract secret/${ES_USER_ID} -n ${ES_NAMESPACE} --keys=password
ES_USER_PWD=`cat password`
cat <<EOF >ace-setdbparms-data-es-scram.txt
truststore::truststorePass dummy $TRUSTSTORE_PWD
kafka::esdemoSecId $ES_USER_ID $ES_USER_PWD

`cat ca.password`
oc extract secret/${ES_INST_NAME}-cluster-ca-cert -n ${ES_NAMESPACE} --keys=ca.p12
keytool -importkeystore -srckeystore ca.p12 -srcstoretype PKCS12 -destkeystore es-cert.jks  -deststoretype JKS -srcstorepass ${TRUSTSTORE_PWD} -deststorepass ${TRUSTSTORE_PWD} -srcalias ca.crt -destalias ca.crt -noprompt
CONFIG_DATA_BASE64=$(base64 -i es-cert.jks)

keytool -import -noprompt \
        -alias gatewayca \
        -file gateway.pem \
        -keystore my.p12 -storetype pkcs12 \
        -storepass password
openssl req -newkey rsa:2048 -nodes -keyout demoapp-mtls-key.pem -x509 -days 365 -out demoapp-mtls-cert.pem
openssl pkcs12 -inkey demoapp-mtls-key.pem -in demoapp-mtls-cert.pem -export -out demoapp-mtls-key.p12

CONFIG_NAME="ace-email-server-policy"
CONFIG_TYPE="policyproject"
CONFIG_NS="tools"
CONFIG_DESCRIPTION="Policy to configure default values for CP4I Demo"
mkdir CP4IEMAIL && cp -a ../cp4i-ace-artifacts/CP4IEMAIL/. CP4IEMAIL/

CONFIG_NAME="ace-email-server-secid"
CONFIG_TYPE="setdbparms"
CONFIG_NS="tools"
CONFIG_DESCRIPTION="Credentials to connect to eMail Server MailTrap"
cat <<EOF >ace-setdbparms-data-email.txt
smtp::mailtrapsecid $MAILTRAP_USER $MAILTRAP_PWD
EOF

# Check if the directory exists
if [ ! -d "$directory" ]; then
    echo "Error: Directory '$directory' not found."
    exit 1
fi

# List files starting with the specified string in the directory
echo "Files starting with '$starting_string' in '$directory':"
find "$directory" -maxdepth 1 -type f -name "${starting_string}*" -exec basename {} \;

mylog info "Building BAR Auth Configuration"
###################
# INPUT VARIABLES #
###################
CONFIG_NAME="github-barauth"
CONFIG_TYPE="barauth"
CONFIG_NS="$MY_ACE_PROJECT"
CONFIG_DESCRIPTION="Authentication for GitHub"
CONFIG_DATA_BASE64=$(base64 -i ${ACE_GEN_CUSTOMDIR}config/template-ace-barauth-data.json)


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

# MQ Integration

export lf_qmgr_name="mainmqm"
if [ ! -d ${SCRIPTDIR}/pol_cp4i_mq ]; then
    mkdir -p ${SCRIPTDIR}/pol_cp4i_mq
fi
cat ${ACE_GEN_CUSTOMDIR}config/pol_mq_cp4i.policyxml | envsubst > ${SCRIPTDIR}/pol_cp4i_mq/pol_mq_cp4i.policyxml
cp ${ACE_GEN_CUSTOMDIR}config/policy.descriptor ${SCRIPTDIR}/pol_cp4i_mq/policy.descriptor
rm pol_cp4i_mq.zip
zip -r pol_cp4i_mq.zip pol_cp4i_mq
rm -R pol_cp4i_mq
CONFIG_CONTENT_BASE64=$(base64 -i ${SCRIPTDIR}pol_cp4i_mq.zip)
mv ${SCRIPTDIR}pol_cp4i_mq.zip ${ACE_GEN_CUSTOMDIR}scripts/pol_cp4i_mq.zip

( echo "cat <<EOF" ; cat ${ACE_GEN_CUSTOMDIR}config/template-ace-config-content.yaml ;) | \
CONFIG_NAME="ace-policy-qm-mainmqm" \
CONFIG_TYPE="policyproject" \
CONFIG_NS="${lf_ace_ns}" \
CONFIG_DESCRIPTION="Policy to connect to ${lf_qmgr_name} Queue Manager" \
CONFIG_CONTENT_BASE64=${CONFIG_CONTENT_BASE64} \
sh > ${ACE_GEN_CUSTOMDIR}scripts/ace-policy-qm-mainmqm.yaml

lf_type="Configuration"
lf_cr_name="ace-policy-qm-mainmqm"
lf_yaml_file="${ACE_GEN_CUSTOMDIR}scripts/ace-policy-qm-mainmqm.yaml"
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"

# TODO check how to update a configuration

lf_type="IntegrationRuntime"
lf_cr_name="ace-paym-proc-api"
lf_yaml_file="${ACE_GEN_CUSTOMDIR}config/ace-ir-paym-proc-api.yaml"
  
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"



# Kafka2Mail

# -----POLICY ES> CP4IESDEMOSCRAM/es-demo.policyxml es-scram
lf_pol_dir="pol_cp4i_kafka"
lf_pol_name="kafka_cp4i"

if [ ! -d ${SCRIPTDIR}/${lf_pol_dir} ]; then
    mkdir -p ${SCRIPTDIR}/${lf_pol_dir}
fi
cat ${ACE_GEN_CUSTOMDIR}config/${lf_pol_name}.policyxml | envsubst > ${SCRIPTDIR}/${lf_pol_dir}/${lf_pol_name}.policyxml
cp ${ACE_GEN_CUSTOMDIR}config/policy.descriptor ${SCRIPTDIR}/${lf_pol_dir}/policy.descriptor
rm ${lf_pol_dir}.zip
zip -r ${lf_pol_dir}.zip ${lf_pol_dir}
rm -R ${lf_pol_dir}
CONFIG_CONTENT_BASE64=$(base64 -i ${SCRIPTDIR}${lf_pol_dir}.zip)
mv ${SCRIPTDIR}${lf_pol_dir}.zip ${ACE_GEN_CUSTOMDIR}scripts/${lf_pol_dir}.zip

( echo "cat <<EOF" ; cat ${ACE_GEN_CUSTOMDIR}config/template-ace-config-content.yaml ;) | \
CONFIG_NAME="ace-policy-kafka-demo" \
CONFIG_TYPE="policyproject" \
CONFIG_NS="${lf_ace_ns}" \
CONFIG_DESCRIPTION="Policy to connect to EventStreams demo" \
CONFIG_CONTENT_BASE64=${CONFIG_CONTENT_BASE64} \
sh > ${ACE_GEN_CUSTOMDIR}scripts/ace-policy-kafka-demo.yaml

lf_type="Configuration"
lf_cr_name="ace-policy-kafka-demo"
lf_yaml_file="${ACE_GEN_CUSTOMDIR}scripts/ace-policy-kafka-demo.yaml"
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_ace_ns}"
# ---- POLICY <
# -----POLICY ES SEC> config-data setdbparms-es
# -----POLICY ES TRUST> config-data truststore-es
# -----POLICY MAIL> config-content policy-email
# -----POLICY MAIL SEC> config-data setdbparms-mail


'