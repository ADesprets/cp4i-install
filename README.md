# cp4i-install


# Directory structure
scriptdir=$(dirname "$0")/	~/installcp4i/ibmcp4i-aspera-test/scripts/
	delete-all.sh
	provision_cluster-v2.sh
yamldir="${scriptdir}tmpl/"	~/installcp4i/ibmcp4i-aspera-test/scripts/tmpl
	ibm-operator-catalog.yaml
	operator-group.yaml
	operator-source-cs.yaml
subscriptionsdir="${scriptdir}tmpl/subscriptions/"	~/installcp4i/ibmcp4i-aspera-test/scripts/tmpl/subscriptions
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
capabilitiesdir="${scriptdir}tmpl/capabilities/"	~/installcp4i/ibmcp4i-aspera-test/scripts/tmpl/capabilities
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
privatedir="${scriptdir}license-key/"	~/installcp4i/ibmcp4i-aspera-test/scripts/tmpl/license-key
	aspera-license
	apikey.json
	ibm_container_entitlement_key.txt


Post install

## *Getting the initial admin password*
https://www.ibm.com/docs/en/cloud-paks/cp-integration/2021.1?topic=installing-getting-initial-admin-password
oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-

## *Fixing the certificate for the Web UI console*

oc -n adcp4i get secret --field-selector type=kubernetes.io/tls | grep zen

oc -n adcp4i get secret iaf-system-automationui-aui-zen-ca -o yaml |grep ca.crt

base 64 decode dans un fichier 
openssl x509 -in c:\temp\t.pem -text

Dans browser imprt Root certificate c:\temp\t.pem 

set srv=cp-console.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
set srv=cpd-adcp4i.adcp4i-par01-b34dfa42ccf328c7da72e2882c1627b1-0000.par01.containers.appdomain.cloud
openssl.exe s_client -showcerts -servername %srv% -connect %srv%:443


oc extract secret/platform-auth-idp-credentials -n ibm-common-services --to=-