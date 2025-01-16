# SFTP site in OpenShift configuration

Excellent information some features need to be updated but very good: <https://medium.com/compendium/install-an-sftp-server-on-openshift-818ea30a4319>

This is the github associated: <https://github.com/atmoz/sftp/blob/master/files/entrypoint>

oc adm policy add-scc-to-user anyuid -z default
In SCC - SecurityContextConstraints

``` yaml
allowedCapabilities:
- SYS_CHROOT
```

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

``` bash
ssh-keygen -t ed25519 -f ssh_host_ed25519_key < /dev/null
ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key < /dev/null
  
echo 123456 > Proto_Passfile
openssl genrsa -des3 -passout file:Proto_Passfile -out ssh_host_os_rsa_key 4096
openssl rsa -pubout -in ssh_host_os_rsa_key -passin file:Proto_Passfile -out ssh_host_os_rsa_key.pub

openssl genpkey -algorithm ed25519 -out ssh_host_os_ed25519_key -outform PEM
openssl pkey -in ssh_host_os_ed25519_key -pubout -out ssh_host_os_ed25519_key.pub

Generate ED25519 key pair:
openssl genpkey -algorithm ed25519 -out ed25519_private.pem
openssl pkey -in ed25519_private.pem -pubout -out ed25519_public.pem
Encrypt data with AES-256:
openssl enc -aes-256-cbc -salt -in plaintext.txt -out encrypted.bin -k password
Decrypt data with AES-256:
openssl enc -d -aes-256-cbc -in encrypted.bin -out decrypted.txt -k password
  
RSA (Rivest–Shamir–Adleman):
Command: openssl genpkey -algorithm RSA
DSA (Digital Signature Algorithm):
Command: openssl dsaparam -out dsaparam.pem 2048 && openssl gendsa -out private_dsa.pem dsaparam.pem
ECDSA (Elliptic Curve Digital Signature Algorithm):
Command: openssl ecparam -name prime256v1 -genkey -noout -out private_ecdsa.pem
Ed25519:
Command: openssl genpkey -algorithm ed25519 -out private_ed25519.pem
DH (Diffie-Hellman):
Command: openssl genpkey -genparam -algorithm DH -out dhparam.pem && openssl genpkey -paramfile dhparam.pem -out private_dh.pem
```

cat /etc/ssh/sshd_config

``` text
# Secure defaults
# See: https://stribika.github.io/2015/01/04/secure-secure-shell.html
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Faster connection
# See: https://github.com/atmoz/sftp/issues/11
UseDNS no

# Limited access
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding no

# Force sftp and chroot jail
Subsystem sftp internal-sftp
ForceCommand internal-sftp
ChrootDirectory %h

# Enable this for more logs
#LogLevel VERBOSE
```

kubectl create configmap my-config --from-literal=key1=value1 --from-literal=key2=value2 --from-literal=key3=value3


sftp -P 30122 sftpsysadmin@sftp-route-sftp.apps.677651fd23fb424f7dff4a9f.ocp.techzone.ibm.com