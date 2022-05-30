ns=$1
oc get subscriptions -n $ns | tail +2 |awk '{print $1}' | xargs oc delete subscription
oc get clusterserviceversion -n $ns | tail +2 |awk '{print $1}' | xargs oc delete clusterserviceversion
