# Certificates Inventory

> All `kind: Certificate` resources defined across the project.

| Certificate Name | File | DNS Names |
|---|---|---|
| `${VAR_CERT_NAME}` | `templates/tls/ca_certificate.yaml` | *(none — CA certificate)* |
| `${VAR_CERT_NAME}` | `templates/tls/ca_certificate_jks.yaml` | *(none — CA certificate with JKS keystore)* |
| `${VAR_CERT_NAME}` | `templates/tls/server_certificate.yaml` | `${VAR_CERT_SAN_DNS_1}`, `${VAR_CERT_SAN_DNS_2}` |
| `${VAR_CERT_NAME}` | `demos/apic_simple/tls/wildcards_certificate.yaml` | `${VAR_CERT_SAN_DNS_1}` |
| `ingress-ca` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — CA certificate)* |
| `analytics-ingestion-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `portal-admin-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `gateway-client-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `gateway-service` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `gateway-peering` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — server + client auth certificate)* |
| `cm-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `admin.${STACK_HOST}`, `admin.${VAR_APIC_NAMESPACE}.svc`, `admin.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `apim-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `manager.${STACK_HOST}`, `manager.${VAR_APIC_NAMESPACE}.svc`, `manager.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `consumer-catalog-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `consumer-catalog.${STACK_HOST}`, `consumer-catalog.${VAR_APIC_NAMESPACE}.svc`, `consumer-catalog.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `api-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `api.${STACK_HOST}`, `api.${VAR_APIC_NAMESPACE}.svc`, `api.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `consumer-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `consumer.${STACK_HOST}`, `consumer.${VAR_APIC_NAMESPACE}.svc`, `consumer.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `analytics-ai-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `ai.${STACK_HOST}`, `ai.${VAR_APIC_NAMESPACE}.svc`, `ai.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `gwv6-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `rgw.${STACK_HOST}`, `rgw.${VAR_APIC_NAMESPACE}.svc`, `rgw.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `gwv6-manager-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `rgwd.${STACK_HOST}`, `rgwd.${VAR_APIC_NAMESPACE}.svc`, `rgwd.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `gwv5-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `gw.${STACK_HOST}`, `gw.${VAR_APIC_NAMESPACE}.svc`, `gw.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `gwv5-manager-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `gwd.${STACK_HOST}`, `gwd.${VAR_APIC_NAMESPACE}.svc`, `gwd.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `portal-admin` | `templates/tls/APIC/custom-certs-external.yaml` | `api.portal.${STACK_HOST}`, `api.portal.${VAR_APIC_NAMESPACE}.svc`, `api.portal.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `portal-web` | `templates/tls/APIC/custom-certs-external.yaml` | `portal.${STACK_HOST}`, `portal.${VAR_APIC_NAMESPACE}.svc`, `portal.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `devportal-admin-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `devportal-wmapigateway-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `wmapigateway-mgmt-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `wmapigateway-devportal-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `nano-gateway-mgmt-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `federatedapimanagement-admin-client` | `templates/tls/APIC/custom-certs-external.yaml` | *(none — client auth certificate)* |
| `devportal-admin` | `templates/tls/APIC/custom-certs-external.yaml` | `api.devportal.${STACK_HOST}`, `api.devportal.${VAR_APIC_NAMESPACE}.svc`, `api.devportal.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `devportal-web` | `templates/tls/APIC/custom-certs-external.yaml` | `devportal.${STACK_HOST}`, `devportal.${VAR_APIC_NAMESPACE}.svc`, `devportal.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `fam-admin-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `api.fam.${STACK_HOST}`, `api.fam.${VAR_APIC_NAMESPACE}.svc`, `api.fam.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `fam-ui-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `fam.${STACK_HOST}`, `fam.${VAR_APIC_NAMESPACE}.svc`, `fam.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `wmapigateway-gw-tls-secret` | `templates/tls/APIC/custom-certs-external.yaml` | `wmapigw-admin.${STACK_HOST}`, `wmapigw-admin.${VAR_APIC_NAMESPACE}.svc`, `wmapigw-admin.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `wmapigateway-mgmt-tls-secret` | `templates/tls/APIC/custom-certs-external.yaml` | `wmapigateway-mgmt.${STACK_HOST}`, `wmapigateway-mgmt.${VAR_APIC_NAMESPACE}.svc`, `wmapigateway-mgmt.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `wmapigateway-ui-tls-secret` | `templates/tls/APIC/custom-certs-external.yaml` | `wmapigw-ui.${STACK_HOST}`, `wmapigw-ui.${VAR_APIC_NAMESPACE}.svc`, `wmapigw-ui.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `gateway-proxy-endpoint` | `templates/tls/APIC/custom-certs-external.yaml` | `apic-gateway-proxy.${STACK_HOST}`, `apic-gateway-proxy.${VAR_APIC_NAMESPACE}.svc`, `apic-gateway-proxy.${VAR_APIC_NAMESPACE}.svc.cluster.local` |
| `stepzen-to-graph-server-cert` | `templates/stepzen/stepzen_2_graph_server_cert.yaml` | `${VAR_SAN_DNS}` |
| `stepzen-to-graph-server-cert` | `templates/stepzen/stepzen-graphql-csr.yaml` | `${VAR_SAN_DNS}` |
| `graphql-to-graph-server-cert` | `templates/stepzen/stepzen-graphql-csr.yaml` | `${VAR_SAN_DNS}` |
| `graphql-to-graph-server-subscriptions-cert` | `templates/stepzen/stepzen-graphql-csr.yaml` | `${VAR_SAN_DNS}` |
| `introspection-cert` | `templates/stepzen/stepzen-graphql-csr.yaml` | `${VAR_SAN_DNS}` |
| `stepzen-to-graph-server-cert` | `templates/stepzen/stepzen-graphql-csr copy.yaml` | `${VAR_SAN_DNS}` |
| `graphql-to-graph-server-cert` | `templates/stepzen/stepzen-graphql-csr copy.yaml` | `${VAR_SAN_DNS}` |
| `graphql-to-graph-server-subscriptions-cert` | `templates/stepzen/stepzen-graphql-csr copy.yaml` | `${VAR_SAN_DNS}` |
| `introspection-cert` | `templates/stepzen/stepzen-graphql-csr copy.yaml` | `${VAR_SAN_DNS}` |
| `introspection-cert` | `templates/stepzen/introspection_cert.yaml` | `${VAR_SAN_DNS}` |
| `graphql-to-graph-server-subscriptions-cert` | `templates/stepzen/graphql_2_graph_server_subscription_cert.yaml` | `${VAR_SAN_DNS}` |
| `graphql-to-graph-server-cert` | `templates/stepzen/graphql_2_graph_server_cert.yaml` | `${VAR_SAN_DNS}` |
| `${VAR_CERT}` | `demos/mq_kafka/tmpl/yaml/qmgr_CACertificate.yaml` | `${VAR_SAN_DNS}` |
| `keycloak-cert` | `templates/keycloak/keycloak-csr.yaml` | `${VAR_SAN_DNS}` |
