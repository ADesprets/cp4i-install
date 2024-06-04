package com.ibm.ad.demo.rest;

// CDI
import jakarta.enterprise.context.RequestScoped;
import jakarta.ws.rs.GET;
// JAX-RS
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@RequestScoped
@Path("/order")
public class OrderResource {

  @GET
  @Produces(MediaType.APPLICATION_JSON)
  public Response getProperties() {


    
    return Response.ok(System.getProperties())
      .header("X-Pod-Name", System.getenv("HOSTNAME"))
      .build();
  }
}
