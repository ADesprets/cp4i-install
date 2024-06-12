package com.ibm.ad.demo.rest.data;

import java.util.UUID;

import com.github.javafaker.Faker;

import jakarta.json.bind.annotation.JsonbNillable;
import jakarta.json.bind.annotation.JsonbProperty;

public class Customer {
    @JsonbNillable
    @JsonbProperty("customerid")
    public String customerid;
    @JsonbProperty("firstname")
    public String firstname;
    @JsonbProperty("lastname")
    public String lastname;

    /** Creates a customer using the provided details. */
    public Customer(String customerid, String firstname, String lastname) {
        this.customerid = customerid;
        this.firstname = firstname;
        this.lastname = lastname;
    }

    public Customer(String firstname, String lastname) {
        this(UUID.randomUUID().toString(), firstname, lastname);
    }

    public Customer(Faker faker) {
        this(UUID.randomUUID().toString(), faker.name().firstName(), faker.name().lastName());
    }

    public String getCustomerid() {
        return customerid;
    }

    public String getFirstname() {
        return firstname;
    }

    public String getLastname() {
        return lastname;
    }

    

}
