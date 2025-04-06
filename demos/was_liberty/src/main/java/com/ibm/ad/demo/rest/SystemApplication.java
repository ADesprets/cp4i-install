package com.ibm.ad.demo.rest;

import java.util.Set;
import java.util.HashSet;
import jakarta.ws.rs.core.Application;
import jakarta.ws.rs.ApplicationPath;

@ApplicationPath("/system")
public class SystemApplication extends Application {
    @Override
    public Set<Class<?>> getClasses() {
        Set<Class<?>> s = new HashSet<Class<?>>();
        s.add(com.ibm.ad.demo.rest.SystemResource.class);
        return s;
    }
}
