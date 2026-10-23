package com.ibm.ad.demo.rest.data;

import jakarta.json.bind.annotation.JsonbProperty;

/**
 * DTO for partial order updates.
 * All fields are optional - only non-null fields will be updated.
 */
public class OrderUpdateRequest {
    
    @JsonbProperty("customerid")
    private String customerid;
    
    @JsonbProperty("customer")
    private String customer;
    
    @JsonbProperty("description")
    private String description;
    
    @JsonbProperty("price")
    private Double price;
    
    @JsonbProperty("quantity")
    private Integer quantity;
    
    @JsonbProperty("region")
    private String region;

    public OrderUpdateRequest() {
        // Default constructor required for JSON-B
    }

    // Getters
    public String getCustomerid() {
        return customerid;
    }

    public String getCustomer() {
        return customer;
    }

    public String getDescription() {
        return description;
    }

    public Double getPrice() {
        return price;
    }

    public Integer getQuantity() {
        return quantity;
    }

    public String getRegion() {
        return region;
    }

    // Setters
    public void setCustomerid(String customerid) {
        this.customerid = customerid;
    }

    public void setCustomer(String customer) {
        this.customer = customer;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public void setPrice(Double price) {
        this.price = price;
    }

    public void setQuantity(Integer quantity) {
        this.quantity = quantity;
    }

    public void setRegion(String region) {
        this.region = region;
    }

    /**
     * Check if at least one field is set for update
     */
    public boolean hasUpdates() {
        return customerid != null || customer != null || description != null || 
               price != null || quantity != null || region != null;
    }

    @Override
    public String toString() {
        return "OrderUpdateRequest{" +
                "customerid='" + customerid + '\'' +
                ", customer='" + customer + '\'' +
                ", description='" + description + '\'' +
                ", price=" + price +
                ", quantity=" + quantity +
                ", region='" + region + '\'' +
                '}';
    }
}
