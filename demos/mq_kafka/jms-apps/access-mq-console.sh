#/bin/bash

echo "--------------------------------------"
echo "Access the MQ web console at this URL:"
echo "--------------------------------------"
$MY_CLUSTER_COMMAND get queuemanager queuemanager -nibmmq -ojsonpath='{.status.adminUiUrl}'

echo ""
echo "---------------"
echo "admin password:"
echo "---------------"
$MY_CLUSTER_COMMAND -n ibm-common-services get secret platform-auth-idp-credentials -ojsonpath='{.data.admin_password}' | base64 --decode ; echo ""
