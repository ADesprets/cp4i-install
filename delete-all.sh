ns=$1
oc get subscriptions -n $ns | tail +2 |awk '{print $1}' | xargs oc delete subscription
oc get clusterserviceversion -n $ns | tail +2 |awk '{print $1}' | xargs oc delete clusterserviceversion
oc delete deployment openldap-2441-centos7
oc delete service openldap-2441-centos7
oc delete route openldap-2441-centos7
