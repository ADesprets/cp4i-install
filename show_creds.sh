#!/bin/bash

# end with / on purpose (if var not defined, uses CWD)
scriptdir=$(dirname "$0")/
privatedir="${scriptdir}private/"

# load helper functions
. "${scriptdir}"lib.sh

read_config_file $1

Login2IBMCloud

Wait4ClusterAvailability

Login2OpenshiftCluster

cat<<EOF
Navigator:
https://$(oc get route  --namespace lm1 ${my_cp_navigator_instance_name}-pn --output=jsonpath='{.spec.host}')
$(oc get secret --namespace ibm-common-services ibm-iam-bindinfo-platform-auth-idp-credentials --output jsonpath={.data.admin_username}|base64 --decode)
$(oc get secret --namespace ibm-common-services ibm-iam-bindinfo-platform-auth-idp-credentials --output jsonpath={.data.admin_password}|base64 --decode)
EOF

exit 0
# TODO: for Aspera
my_nodeadmin_secret_name=${my_cp_hsts_instance_name}-asperanoded-admin
my_node_username=$(oc get secret --namespace ${my_oc_project} ${my_nodeadmin_secret_name} --output jsonpath={.data.user}|base64 --decode)
my_node_password=$(oc get secret --namespace ${my_oc_project} ${my_nodeadmin_secret_name} --output jsonpath={.data.pass}|base64 --decode)
echo https://$(oc get route --selector=name=http-proxy --namespace=$my_oc_project --output=jsonpath='{.items[*].spec.host}')
my_node_url=$()
oc get IbmAsperaHsts --output jsonpath='{.items[?(@.metadata.name=="'${my_cp_hsts_instance_name}'")].status.endpoints[?(@.name=="asperanoded")].uri}'
exit 1
curl -u "$my_node_username:$my_node_password" $my_node_url
echo
