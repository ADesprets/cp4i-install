# cp4i-install

This manual shows how the setup of the following components using one script:

* IBM RedHat Openshift Kubernetes Service (ROKS)
* IBM Cloud Pak for Integration (CP4I) on ROKS

## Preparation

Create a folder for private files:

```bash
mkdir private
```

Save your IBM Cloud API key: Navigate to: [IBM Cloud &rarr; Manage &rarr; Access &rarr; API Keys](https://cloud.ibm.com/iam/apikeys), use or create a new API key, and save to file: `private/apikey.json`.

Save your IBM Marketplace entitlement key: Navigate to [My IBM &rarr; Container software library](https://myibm.ibm.com/products-services/containerlibrary) and save the key in file: `private/ibm_container_entitlement_key.txt`

## Configuration

Copy and *customize* the sample configuration file: `config`

```bash
cp config private/config.mycluster
```

## Usage

Execute the script with the configuration file as parameter. The script is **idempotent**, i.e. it can be stopped and re-executed, it will skip successfully executed commands.

Note: once the Openshift cluster is created, it is required to login once using the web interface to trigger the activation of your api key in the cluster.

For long-running steps, a progress message is displayed.

## Directory structure

```text
/
  delete-all.sh
  provision_cluster-v2.sh
/tmpl
  ibm-operator-catalog.yaml
  operator-group.yaml
  operator-source-cs.yaml
/tmpl/subscriptions
  ACE-Sub.yaml
  APIC-Sub.yaml
  AR-Sub.yaml
  Dashboard-Sub.yaml
  ES-Sub.yaml
  HSTS-Sub.yaml
  MQ-Sub.yaml
  Navigator-Sub.yaml
  Redis-Sub.yaml
  subscription.yaml
/tmpl/capabilities
  ACE-Dashboard-Capability.yaml
  ACE-Designer-Capability.yaml
  APIC-Capability.yaml
  AR-Capability.yaml
  AsperaHSTS-Capability.yaml
  Dashboard-Capability.yaml
  ES-Capability.yaml
  ES-kafka-metrics-ConfigMap.yaml
  ES-zookeeper-metrics-ConfigMap.yaml
  MQ-Capability.yaml
  Navigator-Capability.yaml
  REDIS-Capability.yaml  
/tmpl/license-key
  aspera-license
  apikey.json
  ibm_container_entitlement_key.txt
```

Post install

## Getting the initial admin password

<https://www.ibm.com/docs/en/cloud-paks/cp-integration/2021.1?topic=installing-getting-initial-admin-password>

```bash
oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-
```

## Fixing the certificate for the Web UI console

```bash
oc -n adcp4i get secret --field-selector type=kubernetes.io/tls | grep zen
```

```bash
oc -n adcp4i get secret iaf-system-automationui-aui-zen-ca -o yaml |grep ca.crt
```

base 64 decode dans un fichier

```bash
openssl x509 -in c:\temp\t.pem -text
```

Dans browser imprt Root certificate c:\temp\t.pem 

```cmd
set srv=cp-console.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
set srv=cpd-adcp4i.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
openssl.exe s_client -showcerts -servername %srv% -connect %srv%:443
```

```cmd
oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-
```
