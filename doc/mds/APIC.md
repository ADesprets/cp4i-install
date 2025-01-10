# APIC use cases

## API Tests

![API Test](../images/api_atm-test0.png "API Test")

![API Test](../images/api_atm-test01.png "API Test")

![API Test](../images/api_atm-test02.png "API Test")

![API Test](../images/api_atm-test1.png "API Test")

![API Test](../images/api_atm-test2.png "API Test")

![API Test](../images/api_atm-test3.png "API Test")

![API Test](../images/api_atm-test4.png "API Test")

![API Test](../images/api_atm-test5.png "API Test")

## Backup

``` bash
oc -n cp4i create secret generic apic-mgmt-backup-secret --from-literal=username='foo' --from-literal=password='123'
oc -n cp4i get ManagementCluster
oc -n cp4i get cluster
oc -n cp4i create -f mgmtbackup_cr.yaml
oc -n cp4i get backup -o custom-columns="name:.metadata.name,backupId:.status.backupId,endpoint:.status.endpointURL,path:.status.destinationPath,servername:.status.serverName,status:.status.phase"
```
