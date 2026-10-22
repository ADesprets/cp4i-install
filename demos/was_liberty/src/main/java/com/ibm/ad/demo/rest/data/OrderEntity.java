package com.ibm.ad.demo.rest.data;

import jakarta.persistence.*;
import java.io.Serializable;
import java.time.LocalDateTime;

@Entity
@Table(name = "orders")
@NamedQueries({
    @NamedQuery(name = "OrderEntity.findAll", query = "SELECT o FROM OrderEntity o ORDER BY o.ordertime DESC"),
    @NamedQuery(name = "OrderEntity.findById", query = "SELECT o FROM OrderEntity o WHERE o.id = :id"),
    @NamedQuery(name = "OrderEntity.findByCustomerId", query = "SELECT o FROM OrderEntity o WHERE o.customerid = :customerid ORDER BY o.ordertime DESC"),
    @NamedQuery(name = "OrderEntity.findByRegion", query = "SELECT o FROM OrderEntity o WHERE o.region = :region ORDER BY o.ordertime DESC")
})
public class OrderEntity implements Serializable {
    
    private static final long serialVersionUID = 1L;

    @Id
    @Column(name = "id", nullable = false, length = 36)
    private String id;

    @Column(name = "customerid", nullable = false, length = 36)
    private String customerid;

    @Column(name = "customer", nullable = false, length = 255)
    private String customer;

    @Column(name = "description", nullable = false, length = 500)
    private String description;

    @Column(name = "price", nullable = false)
    private double price;

    @Column(name = "quantity", nullable = false)
    private int quantity;

    @Column(name = "region", nullable = false, length = 50)
    private String region;

    @Column(name = "ordertime", nullable = false)
    private LocalDateTime ordertime;

    public OrderEntity() {
        // Default constructor required by JPA
    }

    public OrderEntity(String id, String customerid, String customer, String description, 
                      double price, int quantity, String region, LocalDateTime ordertime) {
        this.id = id;
        this.customerid = customerid;
        this.customer = customer;
        this.description = description;
        this.price = price;
        this.quantity = quantity;
        this.region = region;
        this.ordertime = ordertime;
    }

    // Getters and Setters
    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getCustomerid() {
        return customerid;
    }

    public void setCustomerid(String customerid) {
        this.customerid = customerid;
    }

    public String getCustomer() {
        return customer;
    }

    public void setCustomer(String customer) {
        this.customer = customer;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public double getPrice() {
        return price;
    }

    public void setPrice(double price) {
        this.price = price;
    }

    public int getQuantity() {
        return quantity;
    }

    public void setQuantity(int quantity) {
        this.quantity = quantity;
    }

    public String getRegion() {
        return region;
    }

    public void setRegion(String region) {
        this.region = region;
    }

    public LocalDateTime getOrdertime() {
        return ordertime;
    }

    public void setOrdertime(LocalDateTime ordertime) {
        this.ordertime = ordertime;
    }

    // Convert to Order DTO
    public Order toOrder() {
        return new Order(
            this.id,
            this.customerid,
            this.customer,
            this.description,
            this.price,
            this.quantity,
            this.region,
            this.ordertime.toString()
        );
    }

    // Create from Order DTO
    public static OrderEntity fromOrder(Order order) {
        OrderEntity entity = new OrderEntity();
        entity.setId(order.getId());
        entity.setCustomerid(order.getCustomerid());
        entity.setCustomer(order.getCustomer());
        entity.setDescription(order.getDescription());
        entity.setPrice(order.getPrice());
        entity.setQuantity(order.getQuantity());
        entity.setRegion(order.getRegion());
        entity.setOrdertime(LocalDateTime.parse(order.getOrdertime().replace(" ", "T")));
        return entity;
    }

    @Override
    public String toString() {
        return "OrderEntity{" +
                "id='" + id + '\'' +
                ", customerid='" + customerid + '\'' +
                ", customer='" + customer + '\'' +
                ", description='" + description + '\'' +
                ", price=" + price +
                ", quantity=" + quantity +
                ", region='" + region + '\'' +
                ", ordertime=" + ordertime +
                '}';
    }
}
