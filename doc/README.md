# Scenario driven CP4I Installation using scripts

## Introduction

The goal is to install a CP4I platform (including Openshift cluster) to demonstrate various scenarios around integration. The installation is started with one command.

The principles followed to implement this asset are the following:

* Automation but highly customizable to choose what capability is needed, and if it must be configured
* Idempotence everywhere
* Expandable by using as much as possible reusable functions to perform any task
* Use of variables as much as possible to reduce the complexity of the code and the number of files
* Reduce dependencies, this is the reason why we do not use ansible playbooks
* Secured by using a private directory where the user has his own credentials
* Follow good practice around scripting
* Run everywhere, the use of ibm-pak allows an installation on IBM Red Hat Openshift in IBM Cloud, onPremise, with CRC - RedHat Code Ready Container, on TechZone. (It has been tested on the three first platforms)
* Install CP4I components but also what is required to have interesting scenarios: LDAP, Mailhog, WAS liberty backends with JAX-RS applications

## Scenarios
	Basics MQ
	Basics ES
	Taxi lab
		Montrer Async API
	Cycle de base d'une API
	Nouvelle version d'une Product (API)
	Auto test/AI Insight
	devOps
	Securité LDAP / Keycloak

	Open Liberty 
		JAX WS
		JAX RS
	Licence service
	noname integration APIC et DP

## Pre-requisites and preliminary tasks

Prerequisites are minimal. There is a method in lib.sh called *check_exec_prereqs* that will ensure at the start of the installation that all utilities are installed.

### Clone repository

Clone the repo locally on your machine:

```bash
git clone https://github.com/ADesprets/cp4i-install
```

### Create files for your credentials

Regarding the access and credentials, you need 3 files to be installed in the private folder.

```bash
  mkdir private
```

| File                              | Description                  | Obtained from  |
| --------------------------------- |:----------------------------:| --------------:|
| apikey.json                       | api key to work in IBM cloud |                |
| ibm_container_entitlement_key.txt | access to image registry     |                |
| user.properties                   | id of the account            |                |

Note that those files in `private` are ignored by git.

1. Navigate to: [IBM Cloud &rarr; Manage &rarr; Access &rarr; API Keys](https://cloud.ibm.com/iam/apikeys), use or create a new API key, and save your IBM Cloud API key **JSON data** to file: `private/apikey.json`. Note that the default configuration file reads the JSON.

1. Navigate to [My IBM &rarr; Container software library](https://myibm.ibm.com/products-services/containerlibrary) and save your IBM Marketplace entitlement key in file: `private/ibm_container_entitlement_key.txt`

1. private/user.properties contains :

``` properties
# For IBM Cloud access
MY_USER_EMAIL='<your email>'
MY_USER_ID="IAM#${MY_USER_EMAIL}"
MY_IMAGE_REGISTRY='<image reigstry>' # example: de.icr.io
MY_IMAGE_REGISTRY_USERNAME='iamapikey'
MY_IMAGE_REGISTRY_PASSWORD='<your password>'
# For TechZone access
MY_TECHZONE_USERNAME=<cluster admininstrator who has access to the cluster, example:  kubeadmin>
MY_TECHZONE_PASSWORD=<cluster admininstrator's password>
MY_TECHZONE_OPENSHIFT_API_URL=<API URL of the cluster, example 'https://api.xxx.cloud.techzone.ibm.com:6443'>
```

TODO Ajouter if Instana alors certificats sur instance Instana SaaS

### Configuration

**Customize** the cp4i.properties file with your own parameters

## Usage

```bash
cd <directory where provision_cluster-v2.sh exists>
./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-2023.4.properties <namespace to deploy capabilities> <cluster_name>
```

## Design

Read this chapter if you want to adapt the scripts to your needs.

* This installation is deploying operators either on a single namespace or in all namespaces in automatic update option

The following tasks will happen:

1. Installation of the OpenShift cluster
2. Installation of the operators of the cloud pak
3. Deployment of the capabilities
4. Configuration of the capabilities

> Hint: The script is using ibm-pak, so it is important to validate that you have the latest version. For more information click [ibm-pak overview](https://github.com/IBM/ibm-pak#overview). To check the version, enter `oc ibm-pak --version`.

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

## Troubleshooting

If you have a timeout error with oc ibm-pak command, you can increase the timeout using the variable IBMPAK_HTTP_TIMEOUT. it is explained at https://github.com/IBM/ibm-pak/blob/main/docs/command-help.md.

## Customisation

1) The source of documents are in the customisation/<capability>/scripts (or config) folders
2) The generated files are in customisation/<capability>/scripts (or config) folders
3) We execute the customisation from customisation/<capability>/scripts

This asset is the result of the collaboration of several people included in the git. You are welcome to join the gang.

## email

Using mailhog as a mail server

oc new-project mail
oc -n mail new-app mailhog/mailhog
oc -n mail expose svc/mailhog --port=8025 --name=mailhogweb
Get the clusterIP
Configure APIC mail
Configure topology

As mail client: Roundcube https://roundcube.net/
