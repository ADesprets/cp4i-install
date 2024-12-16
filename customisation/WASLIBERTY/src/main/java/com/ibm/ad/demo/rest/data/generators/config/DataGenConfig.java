package com.ibm.ad.demo.rest.data.generators.config;

import java.util.List;

public class DataGenConfig {
    // TODO The idea is to use a config file to overwrite the defaut values and
    // make them available for the generators
    // In this version it is hard coded, with a property VALUE, but it should
    // disappear
    // A Holder for all values like org.apache.kafka.common.config.ConfigDef should
    // be used
    public static final String CONFIG_FORMATS_TIMESTAMPS = "formats.timestamps";
    public static final String CONFIG_FORMATS_TIMESTAMPS_LTZ = "formats.timestamps.ltz";
    public static final String CONFIG_LOCATIONS_REGIONS = "locations.regions";
    public static final String CONFIG_PRODUCTS_MIN_PRICE = "prices.min";
    public static final String CONFIG_PRODUCTS_MAX_PRICE = "prices.max";
    public static final String CONFIG_DELAYS_ORDERS = "eventdelays.orders.secs.max";

    public static final String CONFIG_FORMATS_TIMESTAMPS_VALUE = "yyyy-MM-dd HH:mm:ss.SSS";
    public static final String CONFIG_FORMATS_TIMESTAMPS_LTZ_VALUE = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    public static final List<String> CONFIG_LOCATIONS_REGIONS_VALUE = List.of("NA", "SA", "EMEA", "APAC", "ANZ");
    public static final List<String> CONFIG_PRODUCT_MATERIALS_VALUE = List.of("Classic","Retro","Navy","Stonewashed","Acid-washed","Blue","Black","White","Khaki","Denim","Jeggings");
    public static final List<String> CONFIG_PRODUCT_STYLES_VALUE = List.of("Skinny", "Bootcut", "Flare", "Ripped", "Capri", "Jogger", "Crochet", "High-waist", "Low-rise", "Straight-leg", "Boyfriend", "Mom", "Wide-leg", "Jorts", "Cargo", "Tall");
    public static final List<String> CONFIG_PRODUCT_SIZE_VALUE = List.of("XXS", "XS", "S", "M", "L", "XL", "XXL");
    public static final double CONFIG_PRODUCTS_MIN_PRICE_VALUE = 9.99;
    public static final double CONFIG_PRODUCTS_MAX_PRICE_VALUE = 59.99;
    public static final int CONFIG_PRODUCTS_MIN_ITEMS_VALUE = 1;
    public static final int CONFIG_PRODUCTS_MAX_ITEMS_VALUE = 5;
    public static final int CONFIG_DELAYS_ORDERS_VALUE = 0;

}