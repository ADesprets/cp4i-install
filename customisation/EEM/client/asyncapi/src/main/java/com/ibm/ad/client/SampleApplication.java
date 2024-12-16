package com.ibm.ad.client;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.File;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericDatumReader;
import org.apache.avro.generic.GenericRecord;
// import org.apache.avro.io.Decoder;
// import org.apache.avro.io.DecoderFactory;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.config.SslConfigs;

public class SampleApplication {
  public static final void main(String args[]) {  
    Schema.Parser schemaDefinitionParser = new Schema.Parser();
    Schema schema = null;
    try {

      schema = schemaDefinitionParser.parse(new File("D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\customisation\\EEM\\client\\asyncapi\\src\\main\\resources\\LH.ORDERS.avsc"));

    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
    }

    GenericDatumReader<GenericRecord> reader = new GenericDatumReader<GenericRecord>(schema);

    Properties props = new Properties();

    props.put("bootstrap.servers", "cp4i-eg-ibm-egw-rt-1-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com:443");
    props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
    // props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.ByteArrayDeserializer");
    props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");

    props.put("group.id", "1");
    props.put("client.id", "e7915e61-88c8-4eac-bc24-bec1b23c7418");

    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");

    props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
    props.put(SaslConfigs.SASL_JAAS_CONFIG, 
      "org.apache.kafka.common.security.plain.PlainLoginModule required " +
      "username=\"eem-d0472304-b54d-4a2c-8dbf-9a5e5f151c51\" " + 
      "password=\"2da777c1-a000-48eb-afd8-5f970c994b24\";");
    props.put(SslConfigs.SSL_ENABLED_PROTOCOLS_CONFIG, "TLSv1.3");
    props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.3");
    // The Kafka cluster may have encryption enabled. Contact the API owner for the appropriate TrustStore configuration.
    props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\customisation\\EEM\\client\\asyncapi\\src\\main\\resources\\certificate_cp4i-eg-ibm-egw-rt-1-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com_443.pem");
    // props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "TrustPassword123456!");
    props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PEM");

    KafkaConsumer<String, String> consumer = new KafkaConsumer<String, String>(props);
    consumer.subscribe(Collections.singletonList("secctrl"));
    try {
      while(true) {
        ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(10));
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