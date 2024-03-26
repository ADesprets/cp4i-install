sc_properties_file=$1

MAINSCRIPTDIR=${PWD}/
. "${MAINSCRIPTDIR}"lib.sh

# Read all the properties
read_config_file "$sc_properties_file"

#TODO the name of the certificate should be derived from the apic name instance
save_certificate ${MY_APIC_PROJECT} apic-ingress-ca ${WORKINGDIR}
save_certificate ${MY_APIC_PROJECT} apic-gw-gateway ${WORKINGDIR}

      # launch custom script
 mylog info "Customise APIC"
. ${APIC_SCRIPTDIR}scripts/apic.config.sh
