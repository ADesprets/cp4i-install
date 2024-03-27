#!/bin/bash

# end with / on purpose (if var not defined, uses CWD)
mainscriptdir=$(dirname "$0")/
privatedir="${mainscriptdir}private/"

# load helper functions
. "${mainscriptdir}"lib.sh

read_config_file $1

Login2IBMCloud

wait_for_cluster_availability

Login2OpenshiftCluster

cat<<EOF
Navigator:
https://$(oc-n lm1 get route ${my_ibm_navigator_instance_name}-pn --output=jsonpath='{.spec.host}')
$(oc -n ibm-common-services get secret ibm-iam-bindinfo-platform-auth-idp-credentials --output jsonpath={.data.admin_username}|base64 --decode)
$(oc -n ibm-common-services get secret ibm-iam-bindinfo-platform-auth-idp-credentials --output jsonpath={.data.admin_password}|base64 --decode)
EOF

exit 0
# TODO: for Aspera
my_nodeadmin_secret_name=${my_ibm_hsts_instance_name}-asperanoded-admin
my_node_username=$(oc -n ${my_oc_project} get secret ${my_nodeadmin_secret_name} --output jsonpath={.data.user}|base64 --decode)
my_node_password=$(oc -n ${my_oc_project} get secret ${my_nodeadmin_secret_name} --output jsonpath={.data.pass}|base64 --decode)
echo https://$(oc -n $my_oc_project get route --selector=name=http-proxy --output=jsonpath='{.items[*].spec.host}')
my_node_url=$()
oc get IbmAsperaHsts --output jsonpath='{.items[?(@.metadata.name=="'${my_ibm_hsts_instance_name}'")].status.endpoints[?(@.name=="asperanoded")].uri}'
exit 1
curl -u "$my_node_username:$my_node_password" $my_node_url
echo
