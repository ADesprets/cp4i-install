package com.ibm.ad.demo.rest.data;

import jakarta.json.bind.annotation.JsonbNillable;
import jakarta.json.bind.annotation.JsonbProperty;

// {
//   "id": "82a55abc-6c44-4e53-a4c6-03f6d2fb0c0a",
//   "customer": "Lottie Krajcik",
//   "customerid": "03c2ae4d-4d6e-4589-844b-e2a7a90803dd",
//   "description": "S Navy Skinny Jeans",
//   "price": 22.81,
//   "quantity": 10,
//   "region": "APAC",
//   "ordertime": "2024-06-10 19:06:13.969"
// }

public class Order {
    // Public fields are included in the JSON data by default
    @JsonbNillable
    @JsonbProperty("id")
    public String id;
    @JsonbProperty("customerid")
    public String customerid;
    @JsonbProperty("customer")
    public String customer;
    @JsonbProperty("description")
    public String description;
    @JsonbProperty("price")
    public double price;
    @JsonbProperty("quantity")
    public int quantity;
    @JsonbProperty("region")
    public String region;
    @JsonbProperty("ordertime")
    public String ordertime;

    public Order() {
        // A default constructor is required
        // If no default constructor is present, the class must be annotated with
        // @JsonbCreator
    }

    public Order(String id, String customerid, String customer, String description, double price, int quantity,
            String region, String ordertime) {
        this.id = id;
        this.customerid = customerid;
        this.customer = customer;
        this.description = description;
        this.price = price;
        this.quantity = quantity;
        this.region = region;
        this.ordertime = ordertime;
    }

    public String getId() {
        return id;
    }

    public String getCustomer() {
        return customer;
    }

    public String getCustomerid() {
        return customerid;
    }

    public String getDescription() {
        return description;
    }

    public double getPrice() {
        return price;
    }

    public int getQuantity() {
        return quantity;
    }

    public String getRegion() {
        return region;
    }

    public String getOrdertime() {
        return ordertime;
    }

    @Override
    public String toString() {
        StringBuffer sb= new StringBuffer("{");
        sb.append("\"id\" : \"");
        sb.append(getId());
        sb.append("\", \"customerid\" : \"");
        sb.append(getCustomerid());
        sb.append("\", \"customer\" : \"");
        sb.append(getCustomer());
        sb.append("\", \"description\" : \"");
        sb.append(getDescription());
        sb.append("\", \"price\" : ");
        sb.append(getPrice());
        sb.append(", \"quantity\" : ");
        sb.append(getQuantity());
        sb.append(", \"region\" : \"");
        sb.append(getRegion());
        sb.append("\", \"ordertime\" : \"");
        sb.append(getOrdertime());
        sb.append("\"}");
        return sb.toString();
    }
}