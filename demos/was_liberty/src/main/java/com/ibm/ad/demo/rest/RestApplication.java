package com.ibm.ad.demo.rest;

import java.util.Set;
import java.util.HashSet;
import jakarta.ws.rs.core.Application;
import jakarta.ws.rs.ApplicationPath;

@ApplicationPath("/api")
public class RestApplication extends Application {
    @Override
    public Set<Class<?>> getClasses() {
        Set<Class<?>> s = new HashSet<Class<?>>();
        s.add(com.ibm.ad.demo.rest.OrderResource.class);
        return s;
    }
}