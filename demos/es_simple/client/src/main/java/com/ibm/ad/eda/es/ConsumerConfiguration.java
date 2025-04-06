// Copyright 2022 IBM
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
package com.ibm.ad.eda.es;

import java.util.Properties;
import java.io.File;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.kafka.common.serialization.StringDeserializer;

/**
 * ConsumerConfiguration creates the configuration for the Apache Kafka consumer
 * client. See
 * https://cloud.ibm.com/docs/EventStreams?topic=EventStreams-consuming_messages
 * for more information on configuring consumers for use with Event Streams.
 */

public class ConsumerConfiguration {
    public static Properties makeConfiguration(ConsumerCLI args) {
        // The configuration for the apache client is a Properties, with keys defined in
        // the apache client libraries.
        final Properties configs = new Properties();

        // To access the kafka servers, we need to authenticate using SASL_SSL and the
        // apikey, and provide the bootstrap server list

        // SASL_MECHANISM=PLAIN via API key is deprecated, use OAUTHBEARER instead
        // configs.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        // configs.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
        // configs.put(SaslConfigs.SASL_JAAS_CONFIG, String.format(
        // "org.apache.kafka.common.security.plain.PlainLoginModule required
        // username=\"token\" password=\"%s\";", args.apikey));

        ClassLoader classLoader = ConsumerConfiguration.class.getClassLoader();
        File certPemFile = new File(classLoader.getResource("es-cert.p12").getFile());

        configs.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, certPemFile.getAbsolutePath());
        configs.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "SsmWqwkTMwtB");
        configs.put(SslConfigs.SSL_TRUSTSTORE_TYPE_CONFIG, "PKCS12");
        configs.put(SslConfigs.SSL_PROTOCOL_CONFIG, "TLSv1.2");
        configs.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        // configs.put(SaslConfigs.SASL_MECHANISM, "OAUTHBEARER");
        configs.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-512");
        // configs.put(SaslConfigs.SASL_JAAS_CONFIG, String.format(
        // "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required
        // grant_type=\"urn:ibm:params:oauth:grant-type:apikey\" apikey=\"%s\";",
        // args.apikey));
        String saslJaasConfig = "org.apache.kafka.common.security.scram.ScramLoginModule required username=\"es-admin\" password=\"QjsGoBIKQIuIOsdYkUj2dRsbH9vEY7m4\";";
        configs.put(SaslConfigs.SASL_JAAS_CONFIG, saslJaasConfig);
        // configs.put(SaslConfigs.SASL_JAAS_CONFIG,
        // String.format("org.apache.kafka.common.security.plain.PlainLoginModule
        // required username=\"es-admin\"
        // password=\"T2AfpVvyz5j3YhFifGq0pYdBfFpkN5Xv\"));
        // configs.put(SaslConfigs.SASL_LOGIN_CALLBACK_HANDLER_CLASS,
        // "com.ibm.eventstreams.oauth.client.IAMOAuthBearerLoginCallbackHandler");
        // configs.put(SaslConfigs.SASL_OAUTHBEARER_TOKEN_ENDPOINT_URL,
        // "https://iam.cloud.ibm.com/identity/token");
        // configs.put(SaslConfigs.SASL_OAUTHBEARER_JWKS_ENDPOINT_URL,
        // "https://iam.cloud.ibm.com/identity/keys");
        configs.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, args.bootstrapServers);

        // Set up the recommended Event Streams kafka consumer configuration
        // The client ID identifies your client application, and appears in the kafka
        // server logs.
        configs.put(CommonClientConfigs.CLIENT_ID_CONFIG, "eventstreams-java-sample-consumer0");

        // Each consumer is a member of a consumer group, identified by a string
        // (command-line argument in this sample).
        configs.put(ConsumerConfig.GROUP_ID_CONFIG, args.consumerGroup);

        // Part of the consumer's configuration is the classes to use for deserializing
        // data from the records (message) that are received by this consumer.
        // In this sample, we'll assume that the records contain strings.
        configs.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        configs.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());

        return configs;
    }
}
