
# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}../config/"
MAINSCRIPTDIR="${scriptdir}../../../"

# load helper functions
. "${MAINSCRIPTDIR}"lib.sh

read_config_file "${MAINSCRIPTDIR}cp4i.properties"
read_config_file "${configdir}eem-demo.properties"

CreateNameSpace ${eem-demo_project}

echo "MAINSCRIPTDIR: $MAINSCRIPTDIR"
echo "configdir: $configdir"
echo "eem-demo_project: ${eem-demo_project}"

# Deploiement de l'application de backend 
# Work in progress
SECONDS=0
	mylog check "Checking ${octype} ${name} in ${ns}"
	if oc -n ${ns} get deployement ${name} > /dev/null 2>&1; then mylog ok;else
		mylog info "Creating LDAP server"

		# deploy openldap and take in account the PVCs just created
		# check that deployment of openldap was not done
		if oc -n ${ns} get "deployment" "openldap" > /dev/null 2>&1; then mylog ok;else
			oc -n ${ns} new-app osixia/${name}
			oc -n ${ns} get deployment.apps/openldap -o json | jq '. | del(."status")' > ${WORKINGDIR}openldap.json
			jq -s '.[0] * .[1] ' ${WORKINGDIR}openldap.json ${YAMLDIR}kube_resources/ldap-config.json > ${WORKINGDIR}openldap.new.json
			oc -n ldap apply -f ${WORKINGDIR}openldap.new.json

			# expose service externaly and get host and port
			oc -n ${ns} expose service/${name} --target-port=389 --name=openldap-external
			oc -n ${ns} get service ${name} -o json  | jq '.spec.ports[0] += {"Nodeport":30389}' | jq '.spec.ports[1] += {"Nodeport":30686}' | jq '.spec.type |= "NodePort"' | oc apply -f -
			port=`oc -n ${ns} get service ${name} -o jsonpath='{.spec.ports[0].nodePort}'`
			# oc -n ${ns} create route simple ldap-route --service=${openldap-external} --port=389
			hostname=`oc -n ${ns} get route openldap-external -o jsonpath='{.spec.host}'`

			# load users and groups into LDAP
			envsubst < "${YAMLDIR}config/Import.tmpl" > "${YAMLDIR}config/Import.ldiff"
			ldapadd -H ldap://$hostname:$port -D "$ldap_admin_dn" -w "$ldap_admin_password" -f ${YAMLDIR}kube_resources/ldap-users.ldif

			mylog info "You can search entries with the following command: "
			# ldapmodify -H ldap://$hostname:$port -D "$ldap_admin_dn" -w admin -f ${LDAPDIR}Import.ldiff
			# ldapsearch -H ldap://${host}:${port} -x -D "$ldap_admin_dn" -w "$ldap_admin_password" -b "$ldap_base_dn" -s sub -a always -z 1000 "(objectClass=*)"
		fi
	fi

duration=$SECONDS
mylog info "Deployment of the application took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2