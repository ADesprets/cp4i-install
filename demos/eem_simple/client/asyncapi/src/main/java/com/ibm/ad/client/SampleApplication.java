package com.ibm.ad.client;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
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
    // Schema.Parser schemaDefinitionParser = new Schema.Parser();
    //Schema schema = null;
    //try {
//
    //  // eem schema = schemaDefinitionParser.parse(new File("D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\demos\\eem_simple\\client\\asyncapi\\src\\main\\resources\\LH.ORDERS.avsc"));
    //  schema = schemaDefinitionParser.parse(new File("D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\demos\\eem_simple\\client\\asyncapi\\src\\main\\resources\\LH.ORDERS.avsc"));
//
    //} catch (Exception e) {
    //  e.printStackTrace();
    //  System.exit(1);
    //}

    //GenericDatumReader<GenericRecord> reader = new GenericDatumReader<GenericRecord>(schema);

    Properties props = new Properties();

    props.put("bootstrap.servers", "cp4i-es-kafka-bootstrap-cp4i.apps.67ae0126c733f6fb2846efe2.eu1.techzone.ibm.com:443");
    props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
    // props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.ByteArrayDeserializer");
    props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");

    props.put("group.id", "1");
    props.put("client.id", "e7915e61-88c8-4eac-bc24-bec1b23c7418");

    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");

    // Backend can be ES or EEM
    boolean isES=true;
    if (isES) {
      // ES is using SCRAM Properties
      props.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-512");
      String saslJaasConfig = "org.apache.kafka.common.security.scram.ScramLoginModule required "
              + "username=\"es-admin\" password=\"uWx0g8N6UXWPAjJNIcq7tUA3UPxRwQTu\";";
      props.put(SaslConfigs.SASL_JAAS_CONFIG, saslJaasConfig);

      // Mutual auth properties
      //props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SSL");
      //props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, "<java_keystore_file_location>");
      //props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, "<java_keystore_password>");

      // TLS Properties
      props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.2");
      props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\tmp\\es-cert.p12");
      props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "lnrj1rVr6e3a");
      props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PKCS12");
    } else {
      props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
      props.put(SaslConfigs.SASL_JAAS_CONFIG, 
        "org.apache.kafka.common.security.plain.PlainLoginModule required " +
        "username=\"eem-d0472304-b54d-4a2c-8dbf-9a5e5f151c51\" " + 
        "password=\"2da777c1-a000-48eb-afd8-5f970c994b24\";");
      props.put(SslConfigs.SSL_ENABLED_PROTOCOLS_CONFIG, "TLSv1.3");
      props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.3");
      // The Kafka cluster may have encryption enabled. Contact the API owner for the appropriate TrustStore configuration.
      props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "D:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\demos\\eem_simple\\client\\asyncapi\\src\\main\\resources\\certificate_cp4i-eg-ibm-egw-rt-1-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com_443.pem");
      // props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "TrustPassword123456!");
      props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PEM");
      
    }

    KafkaConsumer<String, String> consumer = new KafkaConsumer<String, String>(props);
    consumer.subscribe(Collections.singletonList("LH.ORDERS"));
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
            System.out.println("Region: " + somefield);
          }
        }
    } catch (Exception e) {
      e.printStackTrace();
      consumer.close();
      System.exit(1);
    }   
  }
}