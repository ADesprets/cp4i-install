
# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}../config/"
PROVISION_SCRIPTDIR="${scriptdir}../../../"

# load helper functions
. "${PROVISION_SCRIPTDIR}"lib.sh

read_config_file "${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
read_config_file "${configdir}eem-demo.properties"

CreateNameSpace ${eem-demo_project}

echo "PROVISION_SCRIPTDIR: $PROVISION_SCRIPTDIR"
echo "configdir: $configdir"
echo "eem-demo_project: ${eem-demo_project}"

# Deploiement de l'application de backend 
# Work in progress
SECONDS=0
	mylog check "Checking ${name}/${octype} in ${ns}"
	if ! oc -n ${ns} get deployement ${name} > /dev/null 2>&1; then 
	  mylog info "Creating LDAP server"

	  # deploy openldap and take in account the PVCs just created
	  # check that deployment of openldap was not done
	  if ! oc -n ${ns} get "deployment" "openldap" > /dev/null 2>&1; then 
	  	oc -n ${ns} new-app osixia/${name}
	  	oc -n ${ns} get deployment.apps/openldap -o json | jq '. | del(."status")' > ${MY_WORKINGDIR}openldap.json
	  	jq -s '.[0] * .[1] ' ${MY_WORKINGDIR}openldap.json ${MY_YAMLDIR}kube_resources/ldap_config.json > ${MY_WORKINGDIR}openldap.new.json
	  	oc -n ldap apply -f ${MY_WORKINGDIR}openldap.new.json

		# expose service externaly and get host and port
		oc -n ${ns} expose service/${name} --target-port=389 --name=openldap-external
		oc -n ${ns} get service ${name} -o json  | jq '.spec.ports[0] += {"Nodeport":30389}' | jq '.spec.ports[1] += {"Nodeport":30686}' | jq '.spec.type |= "NodePort"' | oc apply -f -
		port=`oc -n ${ns} get service ${name} -o jsonpath='{.spec.ports[0].nodePort}'`
		# oc -n ${ns} create route simple ldap_route --service=${openldap-external} --port=389
		hostname=`oc -n ${ns} get route openldap-external -o jsonpath='{.spec.host}'`

		# load users and groups into LDAP
		load_users_2_ldap_server "${MY_YAMLDIR}config/" ${MY_WORKINGDIR} "Import.tmpl"
		#envsubst < "${MY_YAMLDIR}config/Import.tmpl" > "${MY_YAMLDIR}config/Import.ldiff"
		#$MY_LDAP_COMMAND -H ldap://$hostname:$port -D "$MY_LDAP_ADMIN_DN" -w "$MY_LDAP_ADMIN_PASSWORD" -f ${MY_YAMLDIR}kube_resources/ldap_users.ldif
	  fi
	fi

duration=$SECONDS
mylog info "Deployment of the application took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2