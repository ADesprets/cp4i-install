package com.ibm.clientengineering.mq.samples;

public class Config {
    public static final String HOST = "PLACEHOLDERHOSTNAME";
    public static final String QMGRNAME = "MYQMGR";
    public static final String CHANNEL = "APP.SVRCONN";
    public static final String QUEUE = "COMMANDS";
    public static final String CIPHER = "ECDHE_RSA_AES_128_CBC_SHA256";

    public static void setupTruststore() {
        System.setProperty("javax.net.ssl.trustStore", "../02-generate-certs/certs/streamingdemo-ca.jks" );
        System.setProperty("javax.net.ssl.keyStore", "../02-generate-certs/certs/streamingdemo-jms-client.jks" );
        System.setProperty("javax.net.ssl.keyStorePassword", "passw0rd" );
        System.setProperty("com.ibm.mq.cfg.useIBMCipherMappings", "false");
    }
}
