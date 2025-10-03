# Demonstration on Event Stream

* Use of datagen to create automatically events on several topics using the datagen code as a custom connector
* Use of the MW Source Connector to demonstrate the integration of MQ and Kafka

## Datagen

## MQ Source connector

### Configuration for the TLS
When using the MQ Source connector with a secured Queue Manager (TLS enabled and authentication). It was cumbersum to find  how to configure it.
Atthe end, we did the following steps:
1) created a secret with only a password that will be used to secure the trustore later on.
2) Create a secrelt from a certificate using the cert manager,  the real trick was to use the instruction to have a jks created in the secret associated to the certificate (keystores> jks > passwordSecretRef). We did this for the root certificate only, leaving the leaf certificate as useual. This chain of certificate was used on the configuration of the queue manager.
3) We mounted the volumes containing the jks into the kafka Connect pods using its CRD.
4) We configured the MQ Source connector to point the mounted jks in the MQ source connector defined in its CRD.