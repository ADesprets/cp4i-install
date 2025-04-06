#/bin/bash

echo "--------------------------------------"
echo "Access the MQ web console at this URL:"
echo "--------------------------------------"
oc get queuemanager queuemanager -nibmmq -ojsonpath='{.status.adminUiUrl}'

echo ""
echo "---------------"
echo "admin password:"
echo "---------------"
oc -n ibm-common-services get secret platform-auth-idp-credentials -ojsonpath='{.data.admin_password}' | base64 --decode ; echo ""
