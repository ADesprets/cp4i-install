/*
* (c) Copyright IBM Corporation 2019, 2024
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

package com.ibm.mq.samples.jms;

import java.util.logging.*;

// Use these imports for building with JMS
import javax.jms.Destination;
import javax.jms.JMSConsumer;
import javax.jms.JMSContext;
import javax.jms.JMSException;
import javax.jms.JMSProducer;
import javax.jms.TextMessage;

import com.ibm.msg.client.jms.JmsConnectionFactory;
import com.ibm.msg.client.jms.JmsFactoryFactory;
import com.ibm.msg.client.wmq.WMQConstants;

import com.ibm.mq.jms.MQDestination;

// Use these imports for building with Jakarta Messaging
// import jakarta.jms.Destination;
// import jakarta.jms.JMSConsumer;
// import jakarta.jms.JMSContext;
// import jakarta.jms.JMSException;
// import jakarta.jms.JMSProducer;
// import jakarta.jms.TextMessage;

// import com.ibm.msg.client.jakarta.jms.JmsConnectionFactory;
// import com.ibm.msg.client.jakarta.jms.JmsFactoryFactory;
// import com.ibm.msg.client.jakarta.wmq.WMQConstants;

// import com.ibm.mq.jakarta.jms.MQDestination;

//import com.ibm.mq.jms.MQConnectionFactory;

import com.ibm.mq.samples.jms.SampleEnvSetter;
import com.ibm.mq.samples.jms.JwtHelper;

public class JmsPut {

    private static final String DEFAULT_APP_NAME = "Dev Experience JmsPut";
    private static final Level LOGLEVEL = Level.ALL;
    private static final Logger logger = Logger.getLogger("com.ibm.mq.samples.jms");

    // Create variables for the connection to MQ
    private static String ConnectionString; //= "localhost(1414),localhost(1416)"
    private static String CHANNEL; // = "DEV.APP.SVRCONN"; // Channel name
    private static String QMGR; // = "QM1"; //System.getenv("QMGR"); // Queue manager name
    private static String APP_USER; // = "app"; // User name that application uses to connect to MQ
    private static String APP_PASSWORD; // = "passw0rd"; // Password that the application uses to connect to MQ
    private static String APP_NAME; // Application Name that the application uses
    private static String QUEUE_NAME; // = "DEV.QUEUE.1"; // Queue that the application uses to put and get messages
                                      // to and from
    private static String CIPHER_SUITE;
    private static String CCDTURL;
    private static Boolean BINDINGS = false;
    private static JwtHelper jh = null;
    private static String accessToken = null;
    
    public static void main(String[] args) {
        initialiseLogging();
        SampleEnvSetter env = new SampleEnvSetter();
        jh = new JwtHelper(env);
        if (jh.isJwtEnabled()) {
            accessToken = jh.obtainToken();
        } else {
            logger.info("One or more JWT Credentials missing! Will not be using JWT for authentication");
        }
        mqConnectionVariables(env);
        logger.info("Put application is starting");

        JMSContext context = null;
        Destination destination = null;
        JMSProducer producer = null;

        JmsConnectionFactory connectionFactory = createJMSConnectionFactory();
        setJMSProperties(connectionFactory);
        logger.info("created connectionfactory");
        context = connectionFactory.createContext();
        logger.info("context created");

        // Set targetClient to be non JMS, so no JMS headers are transmitted.
        // Only one of these settings is required, but both shown here.
        // 1. Add targetClient parameter to Queue uri
        destination = context.createQueue("queue:///" + QUEUE_NAME + "?targetClient=1");
        // destination = context.createQueue("queue:///" + QUEUE_NAME);
        logger.info("destination created");

        // 2. Cast destination queue to underlying MQQueue and set target client
        setTargetClient(destination);

        producer = context.createProducer();
        logger.info("producer created");

        for (int i = 1; i <= 10; i++) {
            TextMessage message = context.createTextMessage("This is message number " + i + ".");
            producer.send(destination, message);
        }
        logger.info("Sent all messages!");
    }

    private static void mqConnectionVariables(SampleEnvSetter env) {
        int index = 0;

        CCDTURL = env.getCheckForCCDT();

        // If the CCDT is in use then a connection string will 
        // not be needed.
        if (null == CCDTURL) {
            ConnectionString = env.getConnectionString();
        }

        CHANNEL = env.getEnvValue("CHANNEL", index);
        QMGR = env.getEnvValue("QMGR", index);
        if (accessToken == null) {
            APP_USER = env.getEnvValue("APP_USER", index);
            APP_PASSWORD = env.getEnvValue("APP_PASSWORD", index);
        }
        APP_NAME = env.getEnvValueOrDefault("APP_NAME", DEFAULT_APP_NAME, index);
        QUEUE_NAME = env.getEnvValue("QUEUE_NAME", index);
        CIPHER_SUITE = env.getEnvValue("CIPHER_SUITE", index);
        BINDINGS = env.getEnvBooleanValue("BINDINGS", index);
    }

    private static JmsConnectionFactory createJMSConnectionFactory() {
        JmsFactoryFactory ff;
        JmsConnectionFactory cf;
        try {
            // JMS
            ff = JmsFactoryFactory.getInstance(WMQConstants.WMQ_PROVIDER);
            // Jakarta
            // ff = JmsFactoryFactory.getInstance(WMQConstants.JAKARTA_WMQ_PROVIDER);

            cf = ff.createConnectionFactory();
        } catch (JMSException jmsex) {
            recordFailure(jmsex);
            cf = null;
        }
        return cf;
    }

    private static void setJMSProperties(JmsConnectionFactory cf) {
        try {
            if (null == CCDTURL) {
                cf.setStringProperty(WMQConstants.WMQ_CONNECTION_NAME_LIST, ConnectionString);
                if (null == CHANNEL && !BINDINGS) {
                    logger.warning("When running in client mode, either channel or CCDT must be provided");
                } else if (null != CHANNEL) {
                    cf.setStringProperty(WMQConstants.WMQ_CHANNEL, CHANNEL);
                }
            } else {
                logger.info("Will be making use of CCDT File " + CCDTURL);
                cf.setStringProperty(WMQConstants.WMQ_CCDTURL, CCDTURL);
                
                // Set the WMQ_CLIENT_RECONNECT_OPTIONS property to allow 
                // the MQ JMS classes to attempt a reconnect 
                // cf.setIntProperty(WMQConstants.WMQ_CLIENT_RECONNECT_OPTIONS, WMQConstants.WMQ_CLIENT_RECONNECT);
            }

            if (BINDINGS) {
                cf.setIntProperty(WMQConstants.WMQ_CONNECTION_MODE, WMQConstants.WMQ_CM_BINDINGS);
            } else {
                cf.setIntProperty(WMQConstants.WMQ_CONNECTION_MODE, WMQConstants.WMQ_CM_CLIENT);
            }

            cf.setStringProperty(WMQConstants.WMQ_QUEUE_MANAGER, QMGR);
            cf.setStringProperty(WMQConstants.WMQ_APPLICATIONNAME, APP_NAME);
            cf.setBooleanProperty(WMQConstants.USER_AUTHENTICATION_MQCSP, true);
            
            setUserCredentials(cf);

            if (CIPHER_SUITE != null && !CIPHER_SUITE.isEmpty()) {
                cf.setStringProperty(WMQConstants.WMQ_SSL_CIPHER_SUITE, CIPHER_SUITE);
            }
        } catch (JMSException jmsex) {
            recordFailure(jmsex);
        }
        return;
    }
    private static void setTargetClient(Destination destination) {
      try {
          MQDestination mqDestination = (MQDestination) destination;
          mqDestination.setTargetClient(WMQConstants.WMQ_CLIENT_NONJMS_MQ);
      } catch (JMSException jmsex) {
        logger.warning("Unable to set target destination to non JMS");
      }
    }

    private static void recordFailure(Exception ex) {
        JmsExceptionHelper.recordFailure(logger,ex);
        return;
    }

    private static void initialiseLogging() {
        Logger defaultLogger = Logger.getLogger("");
        Handler[] handlers = defaultLogger.getHandlers();
        if (handlers != null && handlers.length > 0) {
            defaultLogger.removeHandler(handlers[0]);
        }

        Handler consoleHandler = new ConsoleHandler();
        consoleHandler.setLevel(LOGLEVEL);
        logger.addHandler(consoleHandler);

        logger.setLevel(LOGLEVEL);
        logger.finest("Logging initialised");
    }

    private static void setUserCredentials(JmsConnectionFactory cf) {
        try {
            if (accessToken != null) {
                cf.setStringProperty(WMQConstants.PASSWORD, accessToken);
            } else {
                if (null != APP_USER && !APP_USER.trim().isEmpty()) {
                    cf.setStringProperty(WMQConstants.USERID, APP_USER);
                    cf.setStringProperty(WMQConstants.PASSWORD, APP_PASSWORD);
                }
            }
        } catch (JMSException jmsex) {
            recordFailure(jmsex);
        }
    }
}
