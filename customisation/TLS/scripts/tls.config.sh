################################################################################################
# Start of the script main entry
# main
# This script needs to be started in the same directory as this script.

mylog info "Generate certificate using Certificate manager"

starting=$(date);

scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

# assumptions on the name of the file
read_config_file "${scriptdir}cp4i.properties"

local lf_namespace=cp4i-mq
local lf_issuername=mq
local lf_root_cert_name=mq
local lf_tls_label1=mq-demo
# For TLS Certificate, name needs to be lower cases
local lf_tls_certname=qm1

# For Self-signed issuer
export TLS_CA_ISSUER_NAME=${lf_namespace}-${lf_issuername}-ca
export TLS_NAMESPACE=${lf_namespace}

adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ Issuer_ca.yaml

# For Self-signed Certificate and Root Certificate
export TLS_ROOT_CERT_NAME=${lf_namespace}-${lf_root_cert_name}-ca
export TLS_LABEL1=${lf_tls_label1}
export TLS_CERT_ISSUER_NAME=${lf_namespace}-${lf_issuername}-tls

adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ CACertificate.yaml
adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ Issuer_non_ca.yaml

# For TLS Certificate
export TLS_CERT_NAME=${lf_namespace}-${lf_tls_certname}-tls
export TLS_INGRESS=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ TLSCertificate.yaml

# Create both Issuers and both Certificates
local lf_cert_namespace=${lf_namespace}
local lf_type="Issuer"
local lf_cr_name=${lf_namespace}-${lf_issuername}-ca
local lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/Issuer_ca.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

local lf_cert_namespace=${lf_namespace}
local lf_type="Certificate"
local lf_cr_name=${lf_namespace}-${lf_issuer_cert_name}-ca
local lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/CACertificate.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

local lf_cert_namespace=${lf_namespace}
local lf_type="Issuer"
local lf_cr_name=${lf_namespace}-${lf_issuername}-tls
local lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/Issuer_non_ca.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

local lf_cert_namespace=${lf_namespace}
local lf_type="Certificate"
local lf_cr_name=${lf_namespace}-${lf_tls_certname}-tls
local lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/TLSCertificate.yaml"
decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2