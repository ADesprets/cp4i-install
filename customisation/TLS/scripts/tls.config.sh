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
read_config_file "${scriptdir}properties/cp4i.properties"

local lf_namespace lf_issuername lf_root_cert_name lf_tls_label1 lf_tls_certname

# Create the certificates/secrets required for MQ Configuration
lf_namespace=cp4i-mq
lf_issuername=mq
lf_root_cert_name=mq
lf_tls_label1=mq-demo
# For TLS Certificate, name needs to be lower cases
lf_tls_certname=qm1

create_certificate_chain $lf_namespace $lf_issuername $lf_root_cert_name $lf_tls_label1 $lf_tls_certname


duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2