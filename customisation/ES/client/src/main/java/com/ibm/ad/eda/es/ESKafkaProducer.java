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
        props.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-512");
        props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        props.put("sasl.jaas.config", 
                "org.apache.kafka.common.security.scram.ScramLoginModule required " +
                "username=\"sensors.user1\" " +
                "password=\"yBOaV8EGYKG3PDowD5TMP1w6rBymwBIT\";");

        // Create a new Kafka producer
        KafkaProducer<String, String> producer = new KafkaProducer<>(props);

        // Define the topic and message
        String topic = "LH.SENSORS";
        String key = "1";
        String value = "{\"sensortime\": \"Sun Mar 09 09:22:22 GMT 2025\",\"sensorid\": \"A-2-17\",\"temperature\": 22.5,\"humidity\": 57}";

        // Create a producer record
        ProducerRecord<String, String> record = new ProducerRecord<>(topic, key, value);

        // Send the record
        producer.send(record);

        // Close the producer
        producer.close();
    }
}
