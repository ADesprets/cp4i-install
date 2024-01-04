# cp4i-install

Objectives here:

1 Good quality documentation and shared in GitHub

2 Automation but customizable easily to choose what is needed, idempotent

3 Installation, initial configuration, Advanced configuration

This manual shows how the setup of the following components using one script:

* IBM Red Hat Openshift on IBM Cloud (ROKS)
* IBM Cloud Pak for Integration (CP4I) on ROKS
* This installation is deploying operators either on a single namespace or in all namespaces in automatic update option

The following tasks will happen:

1 Installation of the OpenShift cluster

2 Installation of the operators of the cloud pak

3 Deployment of the capabilities

4 Configuration des capabilities

## Pre-requisites

The following command line tools are used:

* `bash`: Or equivalent (`zsh...`). Command lines in this document assume that a shell such as bash or zsh is used. If another shell is used, adapt the command if necessary. As well as standard shell tools: `sed`, `base64` ...
* `curl`: HTTPS operations are executed using the curl command
* `jq`: jq is used to parse JSON results
* `ibmcloud`: The IBM Cloud CLI.
* `ibm-pak-plugin`: explanation: [installation instructions](https://github.com/IBM/ibm-pak#download-and-verify-software).
* `oc`: The Redhat OpenShift CLI.
* `docker`: The Docker CLI
* `terraform`: The Terraform CLI.

## Installation

Clone the repo locally on your machine:

```bash
git clone https://github.com/ADesprets/cp4i-install
```

## Configuration

1. Create a folder for private configuration files:

```bash
  mkdir private
```

In this folder you can add the various specific files that you are going to use to connect to ibmcloud and access image registry.
It contains:

* apikey.json to login to ibmcloud.
* ibm_container_entitlement_key.txt to access the image registry.

  Note that those files in `private` are ignored by git.

1. Navigate to: [IBM Cloud &rarr; Manage &rarr; Access &rarr; API Keys](https://cloud.ibm.com/iam/apikeys), use or create a new API key, and save your IBM Cloud API key **JSON data** to file: `private/apikey.json`. Note that the default configuration file reads the JSON.

1. Navigate to [My IBM &rarr; Container software library](https://myibm.ibm.com/products-services/containerlibrary) and save your IBM Marketplace entitlement key in file: `private/ibm_container_entitlement_key.txt`

1. **Customize** the cp4i.properties file with your own parameters

> Hint: The script is using ibm-pak, so it is important to validate that you have the latest version. For more information click [ibm-pak overview](https://github.com/IBM/ibm-pak#overview). To check the version, enter `oc ibm-pak --version`.

Good practice:
* Update the capabilities you want to be deployed

## Usage

cd <directory where provision_cluster-v2.sh exists>

> Duration time for all CP4I components including cluster creation: 2 hours 30 min

|===
| Cluster creation | ~ 40 minutes |
| To have ingress available | ~ 10 minutes |
| Adding case | ~ 10 minutes |
| Creation of the operators | ~ 10 minutes |
| Creation of the Navigator instance | ~ 40 minutes |
| Creation of ACE Dashboard instance | ~ 2 minutes |
| Creation of ACE Designer instance | ~ 6 minutes |
| Creation of APIC instance | ~ 30 minutes |
| Creation of Asset Repository instance | ~ 4 minutes |
| Creation of Event Streams instance | ~ 7 minutes |
|===

1. Launch the Shell script

    ```bash
    ./provision_cluster-v2.sh <cp4i.properties file path> <namespace> <cluster_name>
    ```

    example

    ```bash
    ./provision_cluster-v2.sh ./cp4i.properties cp4i cp4i-cluster-2023
    ```

> If you have already created a cluster, the script will install CP4I on top of the existing cluster.
>
> Note: The script is **idempotent**, i.e. it can be stopped and re-executed, it will skip successfully executed commands.
>
> Note: once the Openshift cluster is created, it is required to login once using the web interface to trigger the activation of your api key in the cluster.

For long-running steps, a progress message is displayed.

## Login helper

There is also a helper script to login to ibmcloud and to the cluster if it exists.
You need to change the name of the cluster which is hard coded inside the script or you can pass it as a parameter.

## Directory structure

TO BE REMOVED
Here is the post install directory structure:

```text
D:.
│   .gitignore

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

In your favorite browser import the Root CA certificate c:\temp\t.pem

```cmd
set srv=cp-console.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
set srv=cpd-adcp4i.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
openssl.exe s_client -showcerts -servername %srv% -connect %srv%:443
```

```cmd
oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-
```

## Using terraform for VPC infrastructure

When using VPC (not classic) infrastructure, terraform is used.

Terraform variables are declared in `variables.tf` and have default values.

The main variables (cluster name, flavor, etc...) of the configuration files are forwarded to terraform using env vars prefixed with `TF_VAR_`.

Those variables can also be overridden in file `var_override.tfvars`.

> Duration time: ~ 40+ min

The main script does the following:

1. Export specific configuration values for terraform

    ```bash
    export TF_VAR_xxx=$my_ic_xxx
    ```

1. Go to the terraform folder

    ```bash
    cd terraform
    ```

1. Terraform must fetch the IBM Cloud provider plug-in for Terraform from the Terraform Registry.

    ```bash
    terraform init
    ```

1. Start provisioning

    ```bash
    terraform apply -var-file="testing.auto.tfvars"
    ```

To be moved
In the subscription folder we have the definition of the operators. Since they are all equivalent we do not have one for each component, and use variables that are set at deployment.

## Customisation

1) The source of documents are in the templates/operands-custom/<capability>/scripts (or config) folders
2) The generated files are in customisation/<capability>/scripts (or config) folders
3) We execute the customisation from customisation/<capability>/scripts
