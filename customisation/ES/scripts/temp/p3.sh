GATEWAY_ADDRESS=cp4i-apic-egw-event-gw-client-cp4i.cp4i-cluster-b34dfa42ccf328c7da72e2882c1627b1-0000.eu-de.containers.appdomain.cloud
YOUR-CLIENT-ID=0b98380a91984c3a321906deef1bb408
16718298-7850-4921-bd2c-0ac5a320d91d

~/kafka/kafka_2.13-2.8.0/bin/kafka-console-consumer.sh \
  --bootstrap-server "$GATEWAY_ADDRESS:443" \
  --consumer-property "security.protocol=SASL_SSL" \
  --consumer-property "sasl.mechanism=PLAIN" \
  --consumer-property "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"app\" password=\"password\";" \
  --topic "FLIGHT.LANDINGS" \
  --consumer-property 'client.id=$YOUR-CLIENT-ID' \
  --consumer-property 'ssl.truststore.location=my.p12' \
  --consumer-property 'ssl.truststore.type=PKCS12' \
  --consumer-property 'ssl.truststore.password=password' \
  --consumer-property 'ssl.endpoint.identification.algorithm='
