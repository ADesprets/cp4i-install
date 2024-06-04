package com.ibm.ad.demo.rest.data;
import java.util.Date;
import jakarta.json.bind.annotation.JsonbNillable;
import jakarta.json.bind.annotation.JsonbProperty;

public class Order {
    // Public fields are included in the JSON data by default
    @JsonbNillable
    @JsonbProperty("id") // "20f58c93-5a49-4be8-b03b-25a020ed03e9"
    public String id;
    @JsonbProperty("customer") // "Ms. Yasuko Langworth"
    public String customer;
    @JsonbProperty("customerid") // "675e3b73-aeab-42a6-a5e0-cdf6d48cc67f"
    public String customerid;
    @JsonbProperty("description") // "XXL Jeggings Boyfriend Jeans"
    public String description;
    @JsonbProperty("price") // 45.28
    public long price;
    @JsonbProperty("quantity") // 10
    public int quantity;
    @JsonbProperty("region") // "APAC"
    public String region;
    @JsonbProperty("ordertime") // "2024-06-03 16:27:27.667"
    public Date ordertime;

    // Private fields are ignored by JSON-B by default
    private String somethingSecret = "hello";

    public Order() {
        // A default constructor is required
        // If no default constructor is present, the class must be annotated with @JsonbCreator
    }

    public Order(String id,String customer,String customerid,String description,long price,int quantity,String region,Date ordertime) {
    this.id = id;
    this.customer = customer;
    this.customerid = customerid;
    this.description = description;
    this.price = price;
    this.quantity = quantity;
    this.region = region;
    this.ordertime = ordertime;
    }
}