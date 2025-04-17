# DataPower use case

## Overview

DataPowerService (DPS) - Primary API for managing StatefulSet
DataPowerMonitor (DPM) - Provides monitoring of pod events and gateway peering

Each DataPower application domain is composed with ConfigMaps and Secrets containing the relevant files for the domain file's file system:

* Cert:///
* config:///
* local:///

When ConfigMaps or Secrets are updated a rolling update is performed on the StatefullSet.
passphraseSecret can be used to support decrypting password-alias objects (used to encrypt/decrypt passwords).

``` yaml
spec:
  domains:
  - name: example
    certs:
    - certType: usercerts
      secret: example-certs
    dpApp:
      config:
      - example-config
      local:
      - example-local
    passphrseSecret: example-passphrase
```

Good practice: separate standard configuration files and secret to be in a vault.

One approach to start with is to

* Setup a DataPower instance either with a local docker runtime or using Kubernetes and DataPower operator
* If you are using Docker you will have to mount the relevant directories (config, local, certs, ...)
* Access the CLI, login as admin/admin and enable the GUI
* Develop the service and save the configuration
* Commit the files to the version control

cfg files and config diretories are directly pushed into ConfigMaps
local files aer packed in a tarball and then loaded into a ConfigMap.

It is important to understannd how dpApp configure a domain, see <https://www.ibm.com/docs/en/datapower-operator/1.11?topic=guides-domain-configuration#configuring-a-domain-with-dpapp>.

## gitops

Part 1: Introduction to GitOps Read and Write https://www.ibm.com/support/pages/node/7085880
Part 2: GitOps templating https://www.ibm.com/support/pages/node/7085892
Part 3: GitOps Advanced Configuration https://www.ibm.com/support/pages/node/7085898

## Other informations

### Sample docker setup locally

``` bash
# create a working directory
mkdir dp-dev && cd dep-dev

# setup directories for volume mounts

mkdir config local certs
chmod 777 config local certs

# start DataPower container with volume mounts
docker runt -it \
  -e DATAPOWER_ACCEPT_LICENSE=true \
  -e DATAPOWER_INTERACTIVE=true \
  -v $(pwd)/config:/opt/ibm/datapower/drouter/config \
  -v $(pwd)/local:/opt/ibm/datapower/drouter/local \
  -v $(pwd)/certs:/opt/ibm/datapower/drouter/root/secure/usrcerts \
  -- name dp-dev \
  icr.io/integration/datapower/datapower-limited:10.6.0.1
  ```

### Resources

Documents:

* https://ibm.github.io/datapower-operator-doc/
* https://www.ibm.com/docs/en/datapower-gateways/

Operator scripts:

* https://github.com/IBM/datapower-operator-scripts/

 ``` bash
/datapower
├── domain1
│   ├── config
│   └── local
├── domain2
│   ├── config
│   └── local
└── templates

temporary:///
  gitops/
    resources/
      in/           # On gitops-read, location to put configuration. Watched by configuration sequence.
      out/          # On gitops-write, location to put templated configuration to be committed to Git.
      staging/      # Location to put the source from Git to resolve any templated fields.
    templates/
      in/           # Location to put templates from Git. Watched by configuration sequence.
      out/          # On gitops-write-template, location to put templates to be committed to Git.
```
