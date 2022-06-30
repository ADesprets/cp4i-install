# cp4i-install

This manual shows how the setup of the following components using one script:

* IBM Red Hat Openshift on IBM Cloud (ROKS)
* IBM Cloud Pak for Integration (CP4I) on ROKS

## Pre-requisites

The following command line tools are used:

* `bash`: Or equivalent (`zsh...`). Command lines in this document assume that a shell such as bash or zsh is used. If another shell is used, adapt the command if necessary. As well as standard shell tools: `sed`, `base64` ...
* `curl`: HTTPS operations are executed using the curl command
* `jq`: jq is used to parse JSON results
* `ibmcloud`: The IBM Cloud CLI.
* `oc`: The Redhat OpenShift CLI.
* `docker`: The Docker CLI
* `terraform`: The Terraform CLI.

## Preparation

1. Clone the repo locally on your machine

    ```bash
    git clone https://github.com/ADesprets/cp4i-install
    ```

1. Create a folder for private files:

    ```bash
    mkdir private
    ```

1. Navigate to: [IBM Cloud &rarr; Manage &rarr; Access &rarr; API Keys](https://cloud.ibm.com/iam/apikeys), use or create a new API key, and save your IBM Cloud API key to file: `private/apikey.json`.

1. Navigate to [My IBM &rarr; Container software library](https://myibm.ibm.com/products-services/containerlibrary) and save your IBM Marketplace entitlement key in file: `private/ibm_container_entitlement_key.txt`

## Create an OpenShift cluster in VPC Infrastructure

> Duration time: ~ 40+ min

Let's use Terraform to provision an OpenShift cluster in VPC Infrastruture.

1. Export API credential tokens as environment variables

    ```bash
    export TF_VAR_ibmcloud_api_key="Your IBM Cloud API Key"
    ```

1. Go to the terraform folder

    ```bash
    cd terraform
    ```

1. Terraform must fetch the IBM Cloud provider plug-in for Terraform from the Terraform Registry.

    ```bash
    terraform init
    ```

1. Edit the variables in testing.auto.tfvars if you want to change some services name.

1. Start provisioning

    ```bash
    terraform apply -var-file="testing.auto.tfvars"
    ```

## Configuration

1. Copy and *customize* the sample configuration file: `config`

    ```bash
    cp cp4i.properties.tmpl private/cp4i.properties
    ```

## Usage

> Duration time for all CP4I components: 40 min

1. Execute the script with the configuration file as first parameter or by setting the env var `PC_CONFIG`.

    ```bash
    export PC_CONFIG="$PWD/private/cp4i.properties"
    ```

1. Launch the Shell script

    ```bash
    ./provision_cluster-v2.sh
    ```

> If you have already created a cluster in PVC, the script will install CP4I on top of the existing cluster.
>
> Note: The script is **idempotent**, i.e. it can be stopped and re-executed, it will skip successfully executed commands.
>
> Note: once the Openshift cluster is created, it is required to login once using the web interface to trigger the activation of your api key in the cluster.

For long-running steps, a progress message is displayed.

## Directory structure

Here is the post install directory structure:

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

Dans browser import Root certificate c:\temp\t.pem

```cmd
set srv=cp-console.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
set srv=cpd-adcp4i.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
openssl.exe s_client -showcerts -servername %srv% -connect %srv%:443
```

```cmd
oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-
```
