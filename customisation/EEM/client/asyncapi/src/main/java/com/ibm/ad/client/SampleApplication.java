package com.ibm.ad.client;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.CommonClientConfigs;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.config.SslConfigs;

public class SampleApplication {
  public static final void main(String args[]) {  
    Properties props = new Properties();

    props.put("bootstrap.servers", "cp4i-eg-ibm-egw-rt-cp4i.apps.6637e3708a817e001e4314b5.cloud.techzone.ibm.com:443");
    props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
    props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");

    props.put("group.id", "1");
    props.put("client.id", "e7915e61-88c8-4eac-bc24-bec1b23c7418");

    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");

    props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
    props.put(SaslConfigs.SASL_JAAS_CONFIG, 
      "org.apache.kafka.common.security.plain.PlainLoginModule required " +
      "username=\"eem-fb2ad47b-2cdf-48b7-a5a9-4cefa0de58e0\" " + 
      "password=\"0f317097-0bb0-4411-a718-6a01edae3400\";");
    // props.put(SslConfigs.SSL_ENABLED_PROTOCOLS_CONFIG, "TLSv1.3");
    // props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.3");
    // The Kafka cluster may have encryption enabled. Contact the API owner for the appropriate TrustStore configuration.
    props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\customisation\\EEM\\client\\asyncapi\\src\\main\\resources\\trust.p12");
    props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "TrustPassword123456!");
    props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PKCS12");

    KafkaConsumer consumer = new KafkaConsumer<String, String>(props);
    consumer.subscribe(Collections.singletonList("LH.ORDERS"));
    try {
      while(true) {
        ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(1));
        for (ConsumerRecord<String, String> record : records) {
            String value = record.value();
            System.out.println(value);
            String key = record.key();
            System.out.println(key);
            ObjectMapper om = new ObjectMapper();
            JsonNode jsonNode = om.readTree(value);
            // Do something with your value
            Object somefield = jsonNode.get("region");
            System.out.println(somefield);
          }
        }
    } catch (Exception e) {
      e.printStackTrace();
      consumer.close();
      System.exit(1);
    }   
  }
}