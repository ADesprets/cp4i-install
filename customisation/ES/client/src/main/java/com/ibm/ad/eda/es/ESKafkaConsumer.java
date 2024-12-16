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

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.errors.WakeupException;

/**
 * This is a very simple kafka consumer for an Event Streams instance. It uses
 * an apache kafka consumer client to read and print messages. The consumer runs
 * until the program is stopped with a ctrl-C.
 */
public class ESKafkaConsumer {
    // When using a kafka consumer client, we must close the client when we are done
    // with it. Failing to do this can cause a consumer group rebalance, which can
    // prevent other consumers from reading messages from the topic. These variables
    // are used to close the client when the user enters a ctrl-C.
    static volatile boolean shutdown = false;
    static Thread mainThread = null;
    // The kafka client is parameterized with the key and message types. We are
    // using strings in this simple example.
    static KafkaConsumer<String, String> consumer = null;

    public static void main(String[] args) {
        mainThread = Thread.currentThread();
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            shutdown();
        }));
        
        final ConsumerCLI cliArgs = ConsumerCLI.parse(args);
        final Properties config = ConsumerConfiguration.makeConfiguration(cliArgs);
        
        // The following configuration changes are not recommended practice, although
        // they may be useful for particular applications. They let us adjust the
        // consumer to illustrate Kafka functionality.
        
        config.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, cliArgs.autoCommit);
        config.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, cliArgs.autoOffset);
	    config.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, cliArgs.pollRecords);

        try {
        	// Creation of the consumer may throw an exception, due for example to
        	// bad configuration.
        	consumer = new KafkaConsumer<>(config);
        } catch (Exception e) {
        	System.err.printf("Caught exception creating consumer: %s\n", e.toString());
        	System.exit(1);
        }
        System.out.println("Created consumer");
        
        // Any other exceptions will be caught and cleanly close the kafka client
        try {
            // Subscribe to the topic
            List<String> topics = new ArrayList<String>();
            topics.add(cliArgs.topicName);
            consumer.subscribe(topics);
            final Duration timeout = Duration.ofSeconds(10);
            
            // Poll kafka. The poll returns zero or more records. 
            boolean loop = true;
            while (!shutdown && loop) {
            	loop = cliArgs.pollLoop;
	            final ConsumerRecords<String,String> records = consumer.poll(timeout);
	            System.out.printf("\n** %d records read\n", records.count());
	            for (final ConsumerRecord<String,String> record : records) {
	              	System.out.printf("** read record key='%s', value='%s', topicPartition=%s-%d offset=%d\n",
	                			record.key(),
	                			record.value(),
	                			record.topic(),
	                			record.partition(),
	                			record.offset());
	            }
	            System.out.println();
            }
        } catch (final WakeupException wex) {
            // The ctrl-C shutdown calls the consumer's wakeup() method, which causes a waiting
            // poll() to throw a WakeupException.
        } finally {
            // Close the consumer. This causes it to be cleanly removed from the consumer group.
            if (consumer != null) {
                consumer.close(Duration.ofSeconds(10));
            }
        }
    }

    static void shutdown() {
        System.out.println("Shutting down...");
        if (consumer != null) {
        	// Cause the consumer loop, and any waiting poll(), to exit
            shutdown = true;
            consumer.wakeup();
            try {
                mainThread.join();
            } catch (final InterruptedException e) {
            }
        }
    }
}
