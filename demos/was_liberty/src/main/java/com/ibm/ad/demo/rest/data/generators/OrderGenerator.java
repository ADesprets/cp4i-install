package com.ibm.ad.demo.rest.data.generators;

import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import com.github.javafaker.Faker;
import com.ibm.ad.demo.rest.data.Customer;
import com.ibm.ad.demo.rest.data.Order;
import com.ibm.ad.demo.rest.data.generators.config.DataGenConfig;

// {
//   "id": "82a55abc-6c44-4e53-a4c6-03f6d2fb0c0a",
//   "customerid": "03c2ae4d-4d6e-4589-844b-e2a7a90803dd",
//   "customer": "Lottie Krajcik",
//   "description": "S Navy Skinny Jeans",
//   "price": 22.81,
//   "quantity": 10,
//   "region": "APAC",
//   "ordertime": "2024-06-10 19:06:13.969"
// }

public class OrderGenerator {
    String f = DataGenConfig.CONFIG_FORMATS_TIMESTAMPS_VALUE;
    private final int MAX_DELAY_SECS;

    private final DateTimeFormatter timestampFormatter;
    /** order regions (e.g. NA, EMEA) will be chosen at random from this list */
    private final List<String> regions;

    /** minimum price for randomly selected unit price for generated orders */
    private final double minPrice;
    /** maximum price for randomly selected unit price for generated orders */
    private final double maxPrice;
    /** helper class to randomly generate the name of a product */

    private final Faker faker = new Faker(new Locale("fr"));

    public OrderGenerator() {
        this.regions = DataGenConfig.CONFIG_LOCATIONS_REGIONS_VALUE;
        this.minPrice = DataGenConfig.CONFIG_PRODUCTS_MIN_PRICE_VALUE;
        this.maxPrice = DataGenConfig.CONFIG_PRODUCTS_MAX_PRICE_VALUE;
        this.timestampFormatter = DateTimeFormatter
                .ofPattern(DataGenConfig.CONFIG_FORMATS_TIMESTAMPS_VALUE);
        this.MAX_DELAY_SECS = DataGenConfig.CONFIG_DELAYS_ORDERS_VALUE;
    }

    /** Only one constructor, may need more */
    public Order generate() {
        String orderId = UUID.randomUUID().toString();
        // See if we need a Generator
        Customer customer = new Customer(faker);
        String customerId = customer.getCustomerid();
        String customerName = customer.getFirstname() + " " + customer.getLastname();
        // See if we need a Generator
        String productDescription = BaseGenerator.randomItem(DataGenConfig.CONFIG_PRODUCT_SIZE_VALUE) + " "
                + BaseGenerator.randomItem(DataGenConfig.CONFIG_PRODUCT_MATERIALS_VALUE) + " "
                + BaseGenerator.randomItem(DataGenConfig.CONFIG_PRODUCT_STYLES_VALUE);
        double unitPrice = BaseGenerator.randomDouble(minPrice, maxPrice, 100.0);
        int quantity = BaseGenerator.randomInt(DataGenConfig.CONFIG_PRODUCTS_MIN_ITEMS_VALUE,
                DataGenConfig.CONFIG_PRODUCTS_MAX_ITEMS_VALUE);
        String region = BaseGenerator.randomItem(regions);
        String timeStamp = timestampFormatter.format(BaseGenerator.nowWithRandomOffset(MAX_DELAY_SECS));

        return new Order(orderId, customerId, customerName, productDescription, unitPrice, quantity, region, timeStamp);
    }

    public Order generate(String orderId) {
        // See if we need a Generator
        Customer customer = new Customer(faker);
        String customerId = customer.getCustomerid();
        String customerName = customer.getFirstname() + " " + customer.getLastname();
        // See if we need a Generator
        String productDescription = BaseGenerator.randomItem(DataGenConfig.CONFIG_PRODUCT_SIZE_VALUE) + " "
                + BaseGenerator.randomItem(DataGenConfig.CONFIG_PRODUCT_MATERIALS_VALUE) + " "
                + BaseGenerator.randomItem(DataGenConfig.CONFIG_PRODUCT_STYLES_VALUE);
        double unitPrice = BaseGenerator.randomDouble(minPrice, maxPrice, 100.0);
        int quantity = BaseGenerator.randomInt(DataGenConfig.CONFIG_PRODUCTS_MIN_ITEMS_VALUE,
                DataGenConfig.CONFIG_PRODUCTS_MAX_ITEMS_VALUE);
        String region = BaseGenerator.randomItem(regions);
        String timeStamp = timestampFormatter.format(BaseGenerator.nowWithRandomOffset(MAX_DELAY_SECS));

        return new Order(orderId, customerId, customerName, productDescription, unitPrice, quantity, region, timeStamp);
    }

}
