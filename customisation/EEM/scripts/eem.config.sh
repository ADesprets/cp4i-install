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

# read_config_file "${MY_EEM_GEN_CUSTOMDIR}scripts/eem.properties"

SECONDS=0
# Instruction to create the event gateway in APIC
# Documentation: https://ibm.github.io/event-automation/eem/integrating-with-apic/configure-eem-for-apic/
# 1) JWKSurl: https://cp4i-apic-mgmt-platform-api-cp4i.apps.66c486d0cc846855dd383768.ocp.techzone.ibm.com/api/cloud/oauth2/certs
# 2) ingress certificate (cp4i-apic-ingress-ca) D:\CurrentProjects\CP4I\Installation\cp4i-install\tmp\cp4i-apic-ingress-ca.pem
# kubectl -n <APIC namespace> get secret <ingress-ca name> -ojsonpath="{.data['ca\.crt']}" | base64 -d
# 	oc -n cp4i get secret cp4i-apic-ingress-ca -ojsonpath="{.data['ca\.crt']}" | base64 -d
# 3) secret for EEM apim-cpd.yaml
# 4) Update cp4i-eem CRD
# spec.manager
#     apic:
#       jwks:
#         endpoint: 'https://cp4i-apic-mgmt-platform-api-cp4i.apps.66c486d0cc846855dd383768.ocp.techzone.ibm.com/api/cloud/oauth2/certs'		
# spec.manager.
# tls:
# 	trustedCertificates:
# 	- certificate: ca.crt
# 		secretName: apim-cpd
# 5) Optional, Update cp4i-eem CRD
# spec.manager.apic
# 	clientSubjectDN: CN=IBM Event Endpoint Management
# 6) Get Certificates for API connect
save_certificate ${MY_OC_PROJECT} cp4i-eem-ibm-eem-manager ca.crt ${MY_WORKINGDIR}
save_certificate ${MY_OC_PROJECT} cp4i-eem-ibm-eem-manager tls.crt ${MY_WORKINGDIR}
save_certificate ${MY_OC_PROJECT} cp4i-eem-ibm-eem-manager tls.key ${MY_WORKINGDIR}

# more /home/desprets/installcp4i/working/cp4i-apic-ingress-ca.ca.crt.pem
# more /home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.ca.crt.pem
# more /home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.tls.crt.pem
# more /home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.tls.key.pem
# 
# 7) TlS Profile in APIC EMM Client/EEM Trust
# 	TLS keystore (eem_key)
# 		/home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.tls.crt.pem
# 		/home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.tls.key.pem
# 	TLS truststore (eem_trust)
# 		/home/desprets/installcp4i/working/cp4i-eem-ibm-eem-manager.ca.crt.pem
#   TLS Client profile (eem_TLS_client_profile)
# 8) Register eem-eventgateway
# Service endpoint configuration oc -n cp4i get route | grep apic | grep eem
# 	https://cp4i-eem-ibm-eem-apic-cp4i.apps.66c486d0cc846855dd383768.ocp.techzone.ibm.com
# API invocation endpoint	ibm-egw-rt
# oc -n cp4i get route | grep ibm-egw-rt
# 	cp4i-eg-ibm-egw-rt-1-cp4i.apps.66c486d0cc846855dd383768.ocp.techzone.ibm.com:443

duration=$SECONDS
mylog info "Configuration for Event Endpont Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2