################################################################################################
# Start of the script main entry
# main
# This script ineeds to be started in the same directory as this script.

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
# scriptdir=$(dirname "$0")/
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

# Pas besoin de cela
# read_config_file "${MY_APIC_GEN_CUSTOMDIR}config/apic.properties"

# load users and groups into LDAP
envsubst < "${MY_YAMLDIR}ldap/ldap-users.ldif" > "${MY_WORKINGDIR}ldap-users.ldif"
mylog info "Adding LDAP entries with following command: "
mylog info "$MY_LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${MY_WORKINGDIR}ldap-users.ldif"
$MY_LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -f ${MY_WORKINGDIR}ldap-users.ldif

mylog info "You can search entries with the following command: "
# ldapmodify -H ldap://$lf_hostname:$lf_port0 -D "$ldap_admin_dn" -w admin -f ${MY_LDAPDIR}Import.ldiff
mylog info "ldapsearch -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""
