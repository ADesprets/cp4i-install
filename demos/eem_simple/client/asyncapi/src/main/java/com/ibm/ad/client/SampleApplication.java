package com.ibm.ad.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;

import org.apache.avro.generic.GenericDatumReader;
import org.apache.avro.generic.GenericRecord;
import org.apache.avro.io.EncoderFactory;
import org.apache.avro.io.JsonEncoder;
import org.apache.avro.io.Decoder;
import org.apache.avro.io.DecoderFactory;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.config.SslConfigs;


import org.apache.avro.Schema;
import org.apache.avro.generic.GenericDatumWriter;
import org.apache.avro.io.DatumReader;
import org.apache.kafka.clients.producer.ProducerConfig;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;

public class SampleApplication {
  public static byte[] validateJson(String jsonMessage) throws IOException {
      Schema.Parser parser = new Schema.Parser();
      Schema schema = parser.parse(new File("C:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\demos\\eem_simple\\client\\asyncapi\\src\\main\\resources\\order.produce.avsc"));
      
      // Step 1: VALIDATE JSON → GenericRecord (throws if invalid)
      DatumReader<GenericRecord> reader = new GenericDatumReader<>(schema);
      Decoder decoder = DecoderFactory.get().jsonDecoder(schema, jsonMessage);
      GenericRecord record = reader.read(null, decoder); // Validation happens here!
      
      // Step 2: Serialize validated record to bytes
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      JsonEncoder encoder = EncoderFactory.get().jsonEncoder(schema, out);
      GenericDatumWriter<GenericRecord> writer = new GenericDatumWriter<>(schema);
      writer.write(record, encoder);
      encoder.flush();
      
      return out.toByteArray();
  }

  public static final void main(String args[]) {
    Properties props = new Properties();

    props.put("bootstrap.servers", "iwhi-eg-ibm-egw-rt-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-1-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-10-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-11-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-12-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-13-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-14-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-15-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-16-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-17-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-18-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-19-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-2-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-3-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-4-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-5-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-6-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-7-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-8-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443,iwhi-eg-ibm-egw-rt-9-iwhi.apps.itz-b38e6r.infra01-lb.lon04.techzone.ibm.com:443");
    props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
    // props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.ByteArrayDeserializer");
    props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
    props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.ByteArraySerializer");

    props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");

    props.put("group.id", "1");
    props.put("client.id", "e7915e61-88c8-4eac-bc24-bec1b23c7418");

    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");

    // Backend can be ES or EEM
    boolean isES=false;
    if (isES) {
      // ES is using SCRAM Properties
      props.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-512");
      String saslJaasConfig = "org.apache.kafka.common.security.scram.ScramLoginModule required "
              + "username=\"es-admin\" password=\"XylvKCXHUOpTTB16pSxKGiaCcZmNxUq3\";";
      props.put(SaslConfigs.SASL_JAAS_CONFIG, saslJaasConfig);

      // Mutual auth properties
      //props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SSL");
      //props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, "<java_keystore_file_location>");
      //props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, "<java_keystore_password>");

      // TLS Properties
      props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.2");
      props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "C:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\tmp\\es-cert.p12");
      props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "UFOMvK19gl1M");
      props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PKCS12");
    } else {
      props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
      props.put(SaslConfigs.SASL_JAAS_CONFIG, 
        "org.apache.kafka.common.security.plain.PlainLoginModule required " +
		    "username=\"eem-ef78c1f1-51e2-48a7-85f5-803cc925f306\" " + 
        "password=\"bbefba9c-0069-4e61-bbd3-73f9a3384cc0\";");
      props.put(SslConfigs.SSL_ENABLED_PROTOCOLS_CONFIG, "TLSv1.3");
      props.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.3");
      // The Kafka cluster may have encryption enabled. Contact the API owner for the appropriate TrustStore configuration.
      props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "C:\\CurrentProjects\\CP4I\\Installation\\cp4i-install\\demos\\eem_simple\\client\\asyncapi\\src\\main\\resources\\certificate_iwhi-egrp.pem");
      // props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "TrustPassword123456!");
      props.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PEM");      
    }

    // Consumer or producer
    boolean isConsumer=false;
    if (isConsumer) {
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
    } else {
      KafkaProducer<String, byte[]> producer = new KafkaProducer<String, byte[]>(props);
      try {
        String validJson = """
            {
              "itemID": "INV-12345",
              "label": "Widget A",
              "description": "High-quality widget",
              "category": "Electronics",
              "quantityAvailable": "150",
              "status": "HIGH",
              "format": "Standard",
              "weight": "250",
              "location": "WH-01-A12",
              "lastUpdated": "2026-03-04T08:22:00Z"
            }
            """;
        for (int i = 0; i < 1; i++) {
          byte[] inventoryRecord = validateJson(validJson);
          String topic = "olpo2";
          String key = "INV-12345";

          ProducerRecord<String, byte[]> producerRecord = new ProducerRecord<>(topic, key, inventoryRecord);

          producer.send(producerRecord). get(); // Synchronous send to catch exceptions
          System.out.println("Message sent successfully: " + producerRecord);
        }
      } catch (Exception e) {
        e.printStackTrace();
        producer.close();
        System.exit(1);
      }
    }
  }
}