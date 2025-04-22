package com.stellantis.kafka.replication;

import org.apache.kafka.common.Configurable;
import org.apache.kafka.connect.mirror.ReplicationPolicy;
import org.apache.kafka.connect.mirror.MirrorClientConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.Map;
import java.util.regex.Pattern;
public class KafkaCustomPolicy implements ReplicationPolicy, Configurable{
	private static final Logger log = LoggerFactory.getLogger(KafkaCustomPolicy.class);
    // In order to work with various metrics stores, we allow custom separators.
    public static final String SEPARATOR_CONFIG = MirrorClientConfig.REPLICATION_POLICY_SEPARATOR;
    public static final String SEPARATOR_DEFAULT = ".";
    public static final String INTERNAL_TOPIC_SEPARATOR_ENABLED_CONFIG = MirrorClientConfig.INTERNAL_TOPIC_SEPARATOR_ENABLED;
    public static final Boolean INTERNAL_TOPIC_SEPARATOR_ENABLED_DEFAULT = true;
    private String separator = SEPARATOR_DEFAULT;
    private Pattern separatorPattern = Pattern.compile(Pattern.quote(SEPARATOR_DEFAULT));
    private boolean isInternalTopicSeparatorEnabled = true;
    // patterns is the string that contains the separator after the first default seperator .
    private String patterns = "";

    @Override
    public void configure(Map<String, ?> props) {
        if (props.containsKey(SEPARATOR_CONFIG)) {
        	// Here, the assumption is that customer separator is provided following this format: separator, srcPattern1|replacePattern1,srcPattern2|replacePattern2, ...
            separator = ((String) props.get(SEPARATOR_CONFIG)).split(",")[0];
            patterns = (String) props.get(SEPARATOR_CONFIG);
            log.info("Using custom remote topic separator: '{}'", separator);
            log.info("Using custom remote topic pattern: '{}'", patterns);
            separatorPattern = Pattern.compile(Pattern.quote(separator));
            if (props.containsKey(INTERNAL_TOPIC_SEPARATOR_ENABLED_CONFIG)) {
                isInternalTopicSeparatorEnabled = Boolean.parseBoolean(props.get(INTERNAL_TOPIC_SEPARATOR_ENABLED_CONFIG).toString());
                if (!isInternalTopicSeparatorEnabled) {
                    log.warn("Disabling custom topic separator for internal topics; will use '.' instead of '{}'", separator);
                }
            }
        }
    }

    @Override
    public String formatRemoteTopic(String sourceClusterAlias, String topic) {
    	//Perform replacements
    	log.info("Received topic name is : '{}'", topic);
    	// The assumption is that separator is given as .,sourcePrexi1|targetPrefix1,sourcePrefix2|targetPrefix2,....
    	// If topic name does not contain any prefix, retain the same source name
    	// This is an ugly code :)
    	for (int i = 1; i < patterns.split(",").length; i++ ) {
    		topic=topic.replaceAll(patterns.split(",")[i].split("\\|")[0], patterns.split(",")[i].split("\\|")[1]);
    	}
    	log.info("Returned topic name is : '{}'", topic);
        return topic;
    }

    @Override
    public String topicSource(String topic) {
        String[] parts = separatorPattern.split(topic);
        if (parts.length < 2) {
            // this is not a remote topic
            return null;
        } else {
            return parts[0];
        }
    }

    @Override
    public String upstreamTopic(String topic) {
        String source = topicSource(topic);
        if (source == null) {
            return null;
        } else {
            return topic.substring(source.length() + separator.length());
        }
    }

    private String internalSeparator() {
        return isInternalTopicSeparatorEnabled ? separator : ".";
    }

    private String internalSuffix() {
        return internalSeparator() + "internal";
    }

    private String checkpointsTopicSuffix() {
        return internalSeparator() + "checkpoints" + internalSuffix();
    }

    @Override
    public String offsetSyncsTopic(String clusterAlias) {
        return "mm2-offset-syncs" + internalSeparator() + clusterAlias + internalSuffix();
    }

    @Override
    public String checkpointsTopic(String clusterAlias) {
        return clusterAlias + checkpointsTopicSuffix();
    }

    @Override
    public boolean isCheckpointsTopic(String topic) {
        return  topic.endsWith(checkpointsTopicSuffix());
    }
    
    @Override
    public boolean isMM2InternalTopic(String topic) {
        return  topic.startsWith("mm2") && topic.endsWith(internalSuffix()) || isCheckpointsTopic(topic);
    }
}