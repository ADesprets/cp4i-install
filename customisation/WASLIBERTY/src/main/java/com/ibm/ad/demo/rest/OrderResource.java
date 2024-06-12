package com.ibm.ad.demo.rest;

import com.ibm.ad.demo.rest.data.Order;
import com.ibm.ad.demo.rest.data.generators.OrderGenerator;

// CDI
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.GET;
// JAX-RS
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/order")
@ApplicationScoped
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {
  @GET
  @Path("/{orderId}")
  @Produces(MediaType.APPLICATION_JSON)
  public Response getOrder(@PathParam("orderId") String id) {
    OrderGenerator og = new OrderGenerator();
    Order order = og.generate(id);

    return Response.ok(order)
        .header("X-Pod-Name", System.getenv("HOSTNAME"))
        .build();
  }
}
