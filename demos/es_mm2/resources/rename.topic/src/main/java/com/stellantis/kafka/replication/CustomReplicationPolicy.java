package com.stellantis.kafka.replication;

import org.apache.kafka.connect.mirror.ReplicationPolicy;

public class CustomReplicationPolicy implements ReplicationPolicy {
    private String separator = ".";

    @Override
    public String formatRemoteTopic(String sourceClusterAlias, String topic) {
        return "stellantis" + sourceClusterAlias + separator + topic;
    }

    @Override
    public String topicSource(String topic) {
        int separatorIndex = topic.indexOf(separator);
        return separatorIndex > 0 ? topic.substring(0, separatorIndex) : null;
    }

    @Override
    public void configure(Map<String, ?> configs) {
        if (configs.containsKey("replication.policy.separator")) {
            separator = (String) configs.get("replication.policy.separator");
        }
    }
}