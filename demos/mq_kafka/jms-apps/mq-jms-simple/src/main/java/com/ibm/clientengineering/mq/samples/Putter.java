package com.ibm.clientengineering.mq.samples;

import java.util.Date;

import javax.jms.Connection;
import javax.jms.Destination;
import javax.jms.Message;
import javax.jms.MessageProducer;
import javax.jms.Session;

import com.ibm.msg.client.jms.JmsConnectionFactory;
import com.ibm.msg.client.jms.JmsFactoryFactory;
import com.ibm.msg.client.wmq.WMQConstants;

public class Putter {

    private static void sendMessage(String messagestring, Session session, MessageProducer producer) throws Exception {
        Message message = session.createTextMessage(messagestring);
        producer.send(message);
        System.out.println("sent <" + messagestring + ">");
    }

    public static void main(String[] args) {

        Config.setupTruststore();

        Connection connection = null;
        Session session = null;
        Destination destination = null;
        MessageProducer producer = null;

        try {
            JmsFactoryFactory ff = JmsFactoryFactory.getInstance(WMQConstants.WMQ_PROVIDER);

            JmsConnectionFactory cf = ff.createConnectionFactory();
            cf.setStringProperty(WMQConstants.WMQ_HOST_NAME, Config.HOST);
            cf.setIntProperty(WMQConstants.WMQ_PORT, 443);
            cf.setStringProperty(WMQConstants.WMQ_CHANNEL, Config.CHANNEL);
            cf.setIntProperty(WMQConstants.WMQ_CONNECTION_MODE, WMQConstants.WMQ_CM_CLIENT);
            cf.setStringProperty(WMQConstants.WMQ_QUEUE_MANAGER, Config.QMGRNAME);
            cf.setStringProperty(WMQConstants.WMQ_SSL_CIPHER_SPEC, Config.CIPHER);

            connection = cf.createConnection("mquser", "mquserpassword");
            session = connection.createSession(false, Session.AUTO_ACKNOWLEDGE);

            destination = session.createQueue(Config.QUEUE);
            producer = session.createProducer(destination);

            connection.start();
            sendMessage("Perform the first action A", session, producer);
            sendMessage("Perform a second action B", session, producer);
            sendMessage("Perform the third action C", session, producer);
            sendMessage("Perform some penultimate fourth action D", session, producer);
            sendMessage("Perform a fifth and final action E", session, producer);
            connection.close();
        }
        catch (Exception e) {
            e.printStackTrace();
        }
    }
}
