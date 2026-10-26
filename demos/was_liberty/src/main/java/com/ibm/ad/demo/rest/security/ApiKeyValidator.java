package com.ibm.ad.demo.rest.security;

import jakarta.enterprise.context.ApplicationScoped;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashSet;
import java.util.Properties;
import java.util.Set;
import java.util.logging.Logger;

/**
 * Service to validate API keys.
 * API keys are loaded from apikeys.properties file or environment variables.
 * 
 * Configuration options:
 * 1. File: src/main/resources/apikeys.properties
 *    Format: api.keys=key1,key2,key3
 * 
 * 2. Environment variable: API_KEYS
 *    Format: key1,key2,key3
 * 
 * 3. System property: api.keys
 *    Format: key1,key2,key3
 */
@ApplicationScoped
public class ApiKeyValidator {

    private static final Logger logger = Logger.getLogger(ApiKeyValidator.class.getName());
    private static final String PROPERTIES_FILE = "apikeys.properties";
    private static final String API_KEYS_PROPERTY = "api.keys";
    private static final String API_KEYS_ENV = "API_KEYS";
    
    private final Set<String> validApiKeys;

    public ApiKeyValidator() {
        this.validApiKeys = new HashSet<>();
        loadApiKeys();
        
        if (validApiKeys.isEmpty()) {
            logger.warning("No API keys configured! All requests will be rejected. " +
                         "Please configure API keys via apikeys.properties, API_KEYS environment variable, " +
                         "or api.keys system property.");
        } else {
            logger.info("API key validation initialized with " + validApiKeys.size() + " key(s)");
        }
    }

    /**
     * Validates if the provided API key is valid.
     * 
     * @param apiKey The API key to validate
     * @return true if the API key is valid, false otherwise
     */
    public boolean isValid(String apiKey) {
        if (apiKey == null || apiKey.trim().isEmpty()) {
            return false;
        }
        
        return validApiKeys.contains(apiKey.trim());
    }

    /**
     * Loads API keys from multiple sources in the following priority:
     * 1. System property (api.keys)
     * 2. Environment variable (API_KEYS)
     * 3. Properties file (apikeys.properties)
     */
    private void loadApiKeys() {
        // 1. Try system property first
        String systemKeys = System.getProperty(API_KEYS_PROPERTY);
        if (systemKeys != null && !systemKeys.trim().isEmpty()) {
            addKeys(systemKeys, "system property");
            return;
        }
        
        // 2. Try environment variable
        String envKeys = System.getenv(API_KEYS_ENV);
        if (envKeys != null && !envKeys.trim().isEmpty()) {
            addKeys(envKeys, "environment variable");
            return;
        }
        
        // 3. Try properties file
        loadFromPropertiesFile();
    }

    /**
     * Loads API keys from the properties file.
     */
    private void loadFromPropertiesFile() {
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(PROPERTIES_FILE)) {
            if (input == null) {
                logger.warning("API keys properties file not found: " + PROPERTIES_FILE);
                return;
            }
            
            Properties properties = new Properties();
            properties.load(input);
            
            String keys = properties.getProperty(API_KEYS_PROPERTY);
            if (keys != null && !keys.trim().isEmpty()) {
                addKeys(keys, "properties file");
            } else {
                logger.warning("No API keys found in properties file");
            }
            
        } catch (IOException e) {
            logger.severe("Error loading API keys from properties file: " + e.getMessage());
        }
    }

    /**
     * Adds comma-separated API keys to the valid keys set.
     * 
     * @param keys Comma-separated list of API keys
     * @param source Source of the keys (for logging)
     */
    private void addKeys(String keys, String source) {
        String[] keyArray = keys.split(",");
        int addedCount = 0;
        
        for (String key : keyArray) {
            String trimmedKey = key.trim();
            if (!trimmedKey.isEmpty()) {
                validApiKeys.add(trimmedKey);
                addedCount++;
            }
        }
        
        logger.info("Loaded " + addedCount + " API key(s) from " + source);
    }

    /**
     * Returns the number of configured API keys.
     * Useful for monitoring and diagnostics.
     * 
     * @return Number of valid API keys
     */
    public int getKeyCount() {
        return validApiKeys.size();
    }
}
