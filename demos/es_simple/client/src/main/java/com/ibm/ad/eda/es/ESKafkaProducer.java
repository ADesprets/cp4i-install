package com.ibm.ad.eda.es;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.common.serialization.StringSerializer;

import java.io.File;
import java.util.Properties;
import java.util.UUID;

public class ESKafkaProducer {
    public static void main(String[] args) {
        // Define the properties for the Kafka producer
        Properties props = new Properties();

        ClassLoader classLoader = ConsumerConfiguration.class.getClassLoader();
        File certPemFile = new File(classLoader.getResource("es-cert.p12").getFile());

        props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, certPemFile.getAbsolutePath());
        props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "SsmWqwkTMwtB");
        props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PKCS12");
        props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.2");

        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "cp4i-es-kafka-bootstrap-cp4i.apps.67ae0126c733f6fb2846efe2.eu1.techzone.ibm.com:443");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, "all");

        // Important for ordering and once only once delivery
        props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 1);
        // For Once and only once delivery, but not needed for ordering
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
        
        // TLS configuration
        props.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-512");
        props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        props.put("sasl.jaas.config", 
                "org.apache.kafka.common.security.scram.ScramLoginModule required " +
                "username=\"sensors.user1\" " +
                "password=\"yBOaV8EGYKG3PDowD5TMP1w6rBymwBIT\";");

        // Create a new Kafka producer
        KafkaProducer<String, String> producer = new KafkaProducer<>(props);

        // Define the topic and message

        String topic = "ORDERS.O";
        for (int i = 0; i < 10; i++) {
            String key = UUID.randomUUID().toString();
            // String value = "{\"sensortime\": \"Sun Mar 09 09:22:22 GMT 2025\",\"sensorid\": \"A-2-17\",\"temperature\": 22.5,\"humidity\": 57}";
            String value = "{\"customer\":\"Carrol Hirthe\",\"customerid\":\"0fe41b6c-a9f4-43b8-95ea-6b81aa8c1064\",\"description\":\"XL Classic Jorts Jeans\",\"id\":\"89c3090e-efd9-4873-9d80-a3a782f90dfd\",\"ordertime\":\"2025-03-16 22:00:28.015\",\"price\":26.14,\"quantity\":1,\"region\":\"EMEA\"}";
    
            // Create a producer record
            ProducerRecord<String, String> record = new ProducerRecord<>(topic, key, value);
    
            // Send the record
            producer.send(record);
        }

        // Close the producer
        producer.close();
    }
}
