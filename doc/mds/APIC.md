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

``` bash
kubectl -n <management namespace> create secret generic mgmt-backup-secret --from-literal=username='<username>' --from-file=ssh-privatekey='<privatekeyfile>' [--from-literal=password='<privatekey_passphrase>']
```

``` bash
kubectl -n apic create secret generic mgmt-backup-secret --from-literal=username='itzuser' --from-file=ssh-privatekey='backup.pem'
```

``` bash
kubectl -n <management namespace> edit ManagementCluster
```

``` bash
kubectl -n apic edit ManagementCluster
```

``` bash
  databaseBackup:
    protocol: sftp
    host: 158.175.178.166
    port: 2223
    path: /home/itzuser/backup/apic
    credentials: mgmt-backup-secret
    repoRetentionFull: 14
    schedule: 0 0 1 * * *
```

``` bash
kubectl -n <management namespace> get cluster
kubectl -n apic get cluster
kubectl get cluster -n apic
NAME                     AGE   INSTANCES   READY   STATUS                     PRIMARY
management-ed88e890-db   26d   1           1       Cluster in healthy state   management-ed88e890-db-1
```

``` bash
apiVersion: postgresql.k8s.enterprisedb.io/v1
kind: Backup
metadata:
  generateName: mgmt-backup- # prefix for the name of the backup CR that is generated.
spec:
  cluster:
    name: <database cluster name>
````

``` bash
apiVersion: postgresql.k8s.enterprisedb.io/v1
kind: Backup
metadata:
  generateName: mgmt-backup- # prefix for the name of the backup CR that is generated.
spec:
  cluster:
    name: management-ed88e890-db
```

Create the Backup CR from the mgmtbackup_cr.yaml file:

``` bash
kubectl -n <management namespace> create -f mgmtbackup_cr.yaml
```

Create the Backup CR from the mgmtbackup_cr.yaml file:

``` bash
kubectl -n apic create -f mgmtbackup_cr.yaml
kubectl -n <management namespace> get backup -o custom-columns="name:.metadata.name,backupId:.status.backupId,endpoint:.status.endpointURL,path:.status.destinationPath,servername:.status.serverName,status:.status.phase"
kubectl -n apic get backup -o custom-columns="name:.metadata.name,backupId:.status.backupId,endpoint:.status.endpointURL,path:.status.destinationPath,servername:.status.serverName,status:.status.phase"
name                backupId          endpoint                                   path               servername                                  status
mgmt-backup-bgpbb   20241222T110515   https://management-s3proxy.apic.svc:8765   s3://edb-backups   management-ed88e890-db-2024-11-25T221339Z   completed
```

## Restore

``` bash
kubectl get mgmt -n apic
NAME         READY   STATUS    VERSION         RECONCILED VERSION   MESSAGE               AGE
management   18/18   Running   10.0.8.1-1110   10.0.8.1-1110        Management is ready   87m
kubectl -n <management namespace> get ManagementRestore --sort-by=.metadata.creationTimestamp
kubectl -n apic get ManagementRestore --sort-by=.metadata.creationTimestamp
kubectl -n apic get ManagementRestore --sort-by=.metadata.creationTimestamp
NAME                 STATUS              MESSAGE                                     BACKUP   CLUSTER      PITR   AGE
mgmt-restore-pk4bt   RestoreInProgress   Waiting on management services to disable            management          59s
```

``` yaml
apiVersion: management.apiconnect.ibm.com/v1beta1
kind: ManagementRestore
metadata:
  generateName: mgmt-restore- # this the prefix for the name of the restore CR that is created
spec:
  subsystemName: management
  backup:
    protocol: sftp
    host: 158.175.178.166
    port: 2223
    path: /home/itzuser/backup/apic/management-ed88e890-db-2024-11-25T221339Z
    credentials: mgmt-backup-secret
  backupId: 20241222T110515
```

``` yaml
apiVersion: postgresql.k8s.enterprisedb.io/v1
kind: Backup
metadata:
  generateName: mgmt-backup- # prefix for the name of the backup CR that is generated.
spec:
  cluster:
    name: management-ed88e890-db
```
