################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

# assumptions on the name of the file
read_config_file "${scriptdir}cp4i.properties"
# . "${scriptdir}cp4i.properties"

# read_config_file "${MY_EEM_GEN_CUSTOMDIR}scripts/eem.properties"

SECONDS=0
# Instruction to create the event gateway in APIC
# Documentation: https://ibm.github.io/event-automation/eem/integrating-with-apic/configure-eem-for-apic/

: <<'END_COMMENT'
END_COMMENT

decho 4 "oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="jwksUrl")].uri}'"
lf_jwks_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="jwksUrl")].uri}')
# 2) ingress certificate (cp4i-apic-ingress-ca) D:\CurrentProjects\CP4I\Installation\cp4i-install\tmp\cp4i-apic-ingress-ca.pem
# kubectl -n <APIC namespace> get secret <ingress-ca name> -ojsonpath="{.data['ca\.crt']}" | base64 -d
# 	oc -n cp4i get secret cp4i-apic-ingress-ca -ojsonpath="{.data['ca\.crt']}" | base64 -d
# 3) secret for EEM apim-cpd.yaml


export EEM_APIC_INGRESS_CA_CERT_SECRET_NAME=apim-cpd
if oc -n ${MY_OC_PROJECT} get secret $EEM_APIC_INGRESS_CA_CERT_SECRET_NAME >/dev/null 2>&1; then
    mylog ok
else
    mylog info "Configure Event Endpoint Management to trust API Connect"

    decho 4 "oc -n $MY_OC_PROJECT get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -o=jsonpath=\"{.data['ca\.crt']}\""
    lf_apic_ca_ingress=$(oc -n $MY_OC_PROJECT get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -o=jsonpath="{.data['ca\.crt']}")
    export EEM_APIC_INGRESS_CA_CERT=${lf_apic_ca_ingress}
    adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ apim-cpd.yaml

    # Create Secret to access API Connect from EEM.
    lf_operator_namespace=$MY_OC_PROJECT
    lf_type="Secret"
    lf_cr_name=$EEM_APIC_INGRESS_CA_CERT_SECRET_NAME
    lf_yaml_file="${MY_EEM_GEN_CUSTOMDIR}config/apim-cpd.yaml"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

    # 4) Update cp4i-eem CRD
    # spec.manager
    #     apic:
    #       jwks:
    #         endpoint: 'https://cp4i-apic-mgmt-platform-api-cp4i.apps.66c486d0cc846855dd383768.ocp.techzone.ibm.com/api/cloud/oauth2/certs'		
    # spec.manager.
    #     tls:
    # 	    trustedCertificates:
    # 	    - certificate: ca.crt
    # 		  secretName: apim-cpd
    # Need to restart the pod
    # 5) Optional, Update cp4i-eem CRD
    # spec.manager.apic
    # 	clientSubjectDN: CN=IBM Event Endpoint Management

    # Update the EventEndpointManagement instance with the API Connect configuration details
    decho 4 "oc -n $MY_OC_PROJECT patch EventEndpointManagement "${MY_EEM_INSTANCE_NAME}" --type merge -p '{\"spec\": {"manager": {\"apic\": {\"jwks\": { \"endpoint\": \"$lf_jwks_url\"}}}}}'"
    oc -n $MY_OC_PROJECT patch EventEndpointManagement "${MY_EEM_INSTANCE_NAME}" --type merge -p "{\"spec\" : {\"manager\": {\"apic\": {\"jwks\": {\"endpoint\": \"$lf_jwks_url\"}}}}}"
    # TODO  name of instance (apim-cpd) should in  a variable
    decho 4 "oc -n $MY_OC_PROJECT patch EventEndpointManagement "${MY_EEM_INSTANCE_NAME}" --type merge -p \"{\"spec\":  {\"manager\": {\"tls\": {\"trustedCertificates\": [{\"certificate\": \"ca.crt\"},{\"secretName\": \"$EEM_APIC_INGRESS_CA_CERT_SECRET_NAME\"}]}}}}\""
    oc -n $MY_OC_PROJECT patch EventEndpointManagement "${MY_EEM_INSTANCE_NAME}" --type merge -p '{"spec":{"manager":{"tls":{"trustedCertificates":[{"certificate":"ca.crt","secretName":"apim-cpd"}]}}}}'
fi

# 6) Get Certificates for API connect
save_certificate ${MY_OC_PROJECT} cp4i-eem-ibm-eem-manager ca.crt ${MY_WORKINGDIR}
save_certificate ${MY_OC_PROJECT} cp4i-eem-ibm-eem-manager tls.crt ${MY_WORKINGDIR}
save_certificate ${MY_OC_PROJECT} cp4i-eem-ibm-eem-manager tls.key ${MY_WORKINGDIR}

# 7) TlS Profile in APIC EMM Client/EEM Trust
# Create a TLS Client Profile (eemclientprofile)
# 	Create a TLS keystore (eem_key)
# 		/home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.tls.crt.pem
# 		/home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.tls.key.pem
# 	Create a TLS truststore (eem_trust)
# 		/home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.ca.crt.pem
#   Create a TLS Client profile (eem_TLS_client_profile)
# 8) Register eem-eventgateway eemgtw
# Service endpoint configuration oc -n cp4i get route | grep apic | grep eem
# 	https://cp4i-eem-ibm-eem-apic-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com
# Reference the TLS Client Profile
# API invocation endpoint	ibm-egw-rt
# oc -n cp4i get route | grep ibm-egw-rt
# 	cp4i-eg-ibm-egw-rt-1-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com:443

duration=$SECONDS
mylog info "Configuration for Event Endpont Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2