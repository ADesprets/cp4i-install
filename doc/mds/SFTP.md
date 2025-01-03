# SFTP site in OpenShift configuration

Excellent information some features need to be updated but cery good: <https://medium.com/compendium/install-an-sftp-server-on-openshift-818ea30a4319>

oc adm policy add-scc-to-user anyuid -z default
In SCC - SecurityContextConstraints

``` yaml
allowedCapabilities:
- SYS_CHROOT
```

<https://medium.com/compendium/install-an-sftp-server-on-openshift-818ea30a4319>

oc new-project int-sftp --display-name="Internal sftp server"
oc -n int-sftp new-app atmoz/sftp:alpine

oc adm policy add-scc-to-user anyuid -z default

``` yaml
      volumes:
        - name: users
          configMap:
            name: sftp-etc-sftp
            defaultMode: 420
      containers:
        - name: sftp
          volumeMounts:
            - name: users
              readOnly: true
              mountPath: /etc/sftp
```

Create config map for ssh using ssh key-gen commands
Change to defaultMode: 384 setting for sftp-stc-ssh

``` yaml
      volumes:
        - configMap:
          defaultMode: 384
          name: sftp-etc-ssh
```

Create Persistent Volume
 Name: sftp-bar-storage
 Access Mode: Shared Access (RWX)
 Size: 10 GiB

Test
oc -n int-sftp get svc
sftp -P 30022 <bar@sftp-int-sftp.apps.677651fd23fb424f7dff4a9f.ocp.techzone.ibm.com>

``` yaml
    databaseBackup:
      credentials: apic-mgmt-backup-secret
      host: sftp-int-sftp.apps.677651fd23fb424f7dff4a9f.ocp.techzone.ibm.com
      path: /upload
      port: 30022
      protocol: sftp
      repoRetentionFull: 14
      schedule: 0 0 1 * * *
```

``` yaml
      protocol: local
      repoRetentionFull: 14
      schedule: 0 0 1 * * *
```
