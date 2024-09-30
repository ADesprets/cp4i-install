package com.ibm.ad.eda.es;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;

/**
 * ConsumerCLI parses the command-line arguments for the consumer client sample.  The parsing
 * itself is irrelevant to the configuration and operation of the Kafka consumer client.
 * 
 * -a apikey, --apikey apikey
 * The apikey, from the credentials for the Event Streams instance. Required.
 * 
 * -b bootstrapServers, --bootstrap bootstrapServers
 * The kafka bootstrap servers list, from the credentials for the instance; as a string of comma-separated broker names. Required.
 * 
 * -t topicName, --topic topicName
 * The topic name; the topic must have been created. Required.
 * 
 * -g consumerGroup, --group consumerGroup
 * The consumer group identifier. Optional, defaults to 'consumer group'.
 * 
 * The following options are for configuring the consume and commit behavior of this sample.
 * 
 * -c autoCommit, --autoCommit autoCcommit
 * Whether to auto-commit. Optional, default to true; anything other than "true" is treated as false.
 * 
 * -o autoOffset, --autoOffset autoOffset
 * Auto-offset setting, either 'earliest' or 'latest'. Optional, defaults to 'latest'; anything other than 'latest' is treated as 'earliest'.
 * 
 * -p pollRecords, --pollRecords pollRecords
 * Maximum poll records. Optional, default to 500.
 * 
 * -l loop, --loop loop
 * Whether to continue polling in a loop. Optional, default to false.
 * 
 */
public class ConsumerCLI {

    final String apikey;
	final String bootstrapServers;
	final String topicName;
	final String consumerGroup;
	final boolean autoCommit;
	final String autoOffset;
	final int pollRecords;
	final boolean pollLoop;
	
	private ConsumerCLI(String apikey, String bootstrapServers, String topicName, String consumerGroup, boolean autoCommit, String autoOffset, int pollRecords, boolean pollLoop) {
		this.apikey = apikey;
		this.bootstrapServers = bootstrapServers;
		this.topicName = topicName;
		this.consumerGroup = consumerGroup;
		this.autoCommit = autoCommit;
		this.autoOffset = autoOffset;
		this.pollRecords = pollRecords;
		this.pollLoop = pollLoop;
	}
	
	static ConsumerCLI parse(String[] args) { 
		Options options = new Options();
		
		options.addOption(
				Option.builder("a")
					.longOpt("apikey")
					.hasArg(true)
					.argName("apikey")
					.desc("(required) apikey from the credentials for your Event Streams instance")
					.required()
					.build());
		options.addOption(
				Option.builder("b")
					.longOpt("bootstrap")
					.hasArg(true)
					.argName("bootstrapServers")
					.desc("(required) bootstrap servers from the credentials for your Event Streams instance, as a comma-separated list")
					.required()
					.build());
		options.addOption(
				Option.builder("t")
					.longOpt("topic")
					.hasArg(true)
					.argName("topicName")
					.desc("(required) name of the Kafka topic, which you must have already created")
					.required()
					.build());
		options.addOption(
				Option.builder("g")
					.longOpt("group")
					.hasArg(true)
					.argName("consumerGroup")
					.desc("(optional, default 'consumerGroup') consumer group identifier")
					.required(false)
					.build());
		options.addOption(
				Option.builder("c")
					.longOpt("autoCommit")
					.hasArg(true)
					.argName("autoCommit")
					.desc("(optional, default 'true') whether to auto-commit")
					.required(false)
					.build());
		options.addOption(
				Option.builder("o")
					.longOpt("autoOffset")
					.hasArg(true)
					.argName("autoOffset")
					.desc("(optional, default 'latest') auto-offset setting, options are 'earliest' and 'latest'")
					.required(false)
					.build());
		options.addOption(
				Option.builder("p")
					.longOpt("pollRecords")
					.hasArg(true)
					.argName("pollRecords")
					.desc("(optional, default '500') maximum number of records returned by poll")
					.required(false)
					.build());
		options.addOption(
				Option.builder("l")
					.longOpt("loop")
					.hasArg(true)
					.argName("loop")
					.desc("(optional, default false) whether to continue polling in a loop")
					.required(false)
					.build());
		
		CommandLine cmd = null;
		try {
			cmd = new DefaultParser().parse(options, args);
		} catch (Exception e) {
			printHelpAndExit(e.toString(), options);
		}
		
		String apikey = cmd.getOptionValue("a");
		String bootstrapServers = cmd.getOptionValue("b");
		String topicName = cmd.getOptionValue("t");
		String consumerGroup = cmd.getOptionValue("g", "consumerGroup");
		boolean autoCommit = "true".equals(cmd.getOptionValue("c", "true"));
		String autoOffset = cmd.getOptionValue("o", "latest");
		if (!"earliest".equals(autoOffset)) {
			autoOffset = "latest";
		}
		int pollRecords = 500;
		try {
			pollRecords = Integer.parseInt(cmd.getOptionValue("p", "500"));
			if (pollRecords <= 0) {
				printHelpAndExit("Invalid pollRecords value, must be greater than 0", options);
			}
		} catch (Exception e) {
			printHelpAndExit("Invalid pollRecords value", options);
		}
		boolean pollLoop = "true".equals(cmd.getOptionValue("l", "false"));
		
		return new ConsumerCLI(apikey, bootstrapServers, topicName, consumerGroup, autoCommit, autoOffset, pollRecords, pollLoop);
	}
	
	static void printHelpAndExit(String emessage, Options options) {
		System.err.printf("Incorrect command line arguments: %s\n", emessage);
	    HelpFormatter formatter = new HelpFormatter();
	    formatter.printHelp("consumer", options);
	    System.exit(1);
	}
}
