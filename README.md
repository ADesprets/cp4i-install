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
