package com.ibm.clientengineering.mq.samples;

import javax.jms.Connection;
import javax.jms.Destination;
import javax.jms.Message;
import javax.jms.MessageConsumer;
import javax.jms.Session;

import com.ibm.msg.client.jms.JmsConnectionFactory;
import com.ibm.msg.client.jms.JmsFactoryFactory;
import com.ibm.msg.client.wmq.WMQConstants;

public class Getter {
    public static void main(String[] args) {

        Config.setupTruststore();

        Connection connection = null;
        Session session = null;
        Destination destination = null;
        MessageConsumer consumer = null;

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
            consumer = session.createConsumer(destination);

            connection.start();

            Message message = null;
            while ((message = consumer.receive(2000)) != null) {
                System.out.println(message.toString());
            }

            connection.close();
        }
        catch (Exception e) {
            e.printStackTrace();
        }
    }
}
