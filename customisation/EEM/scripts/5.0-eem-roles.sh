
. ./env.sh

roles='{\"mappings\":[ {\"id\":\"admin\",\"roles\":[\"admin\",\"author\"]},  {\"id\":\"eventendpointmanagement-admin\",\"roles\":[\"admin\",\"author\"]}, {\"id\":\"eem-admin\",\"roles\":[\"admin\"]}, {\"id\":\"integration-admin\",\"roles\":[\"admin\",\"author\"]}, {\"id\":\"eventendpointmanagement-viewer\",\"roles\":[\"viewer\"]}, {\"id\":\"eem-user\",\"roles\":[\"viewer\"]}, {\"id\":\"eem-author\",\"roles\":[\"author\"]},  {\"id\":\"author\",\"roles\":[\"author\"]} ]}'

secret_roles=$(oc get -n $NAMESPACE secret |grep ibm-eem-user-roles | awk '{ print $1 }')

kubectl patch secret $secret_roles  --patch="{\"stringData\": { \"user-mapping.json\": \"$( echo -n $roles )\" }}"

oc delete po -n $NAMESPACE eem1-ibm-eem-manager-0 &
sleep 60

while [ $( oc get po --no-headers  -n $NAMESPACE | grep eem1-ibm-eem-manager-0  |grep Running  |grep '1/1' | wc -l ) -eq 0 ]
do
    oc get po --no-headers  -n $NAMESPACE | grep eem1-ibm-eem-manager-0 
    sleep 10
done

