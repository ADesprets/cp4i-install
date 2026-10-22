package com.ibm.ad.demo.rest;

import com.ibm.ad.demo.rest.data.Order;
import com.ibm.ad.demo.rest.service.OrderService;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.logging.Logger;

@Path("/orderp")
@ApplicationScoped
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class OrderResourceP {

    private static final Logger logger = Logger.getLogger(OrderResourceP.class.getName());

    @Inject
    private OrderService orderService;

    /**
     * Create a new order
     * POST /api/orderp
     */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response createOrder(Order order) {
        logger.info("Creating new order via REST API");
        
        try {
            if (order == null) {
                return Response.status(Response.Status.BAD_REQUEST)
                    .entity("{\"error\": \"Order data is required\"}")
                    .build();
            }

            // Validate required fields
            if (order.getCustomer() == null || order.getCustomer().isEmpty()) {
                return Response.status(Response.Status.BAD_REQUEST)
                    .entity("{\"error\": \"Customer name is required\"}")
                    .build();
            }

            Order createdOrder = orderService.createOrder(order);
            
            return Response.status(Response.Status.CREATED)
                .entity(createdOrder)
                .header("X-Pod-Name", System.getenv("HOSTNAME"))
                .build();
                
        } catch (Exception e) {
            logger.severe("Error creating order: " + e.getMessage());
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity("{\"error\": \"Failed to create order: " + e.getMessage() + "\"}")
                .build();
        }
    }

    /**
     * Get order by ID
     * GET /api/orderp/{orderId}
     */
    @GET
    @Path("/{orderId}")
    @Produces(MediaType.APPLICATION_JSON)
    public Response getOrder(@PathParam("orderId") String orderId) {
        logger.info("Fetching order with ID: " + orderId);
        
        try {
            Order order = orderService.getOrderById(orderId);
            
            if (order == null) {
                return Response.status(Response.Status.NOT_FOUND)
                    .entity("{\"error\": \"Order not found with ID: " + orderId + "\"}")
                    .build();
            }
            
            return Response.ok(order)
                .header("X-Pod-Name", System.getenv("HOSTNAME"))
                .build();
                
        } catch (Exception e) {
            logger.severe("Error fetching order: " + e.getMessage());
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity("{\"error\": \"Failed to fetch order: " + e.getMessage() + "\"}")
                .build();
        }
    }

    /**
     * Get all orders with pagination support
     * GET /api/orderp?offset=0&limit=10
     * GET /api/orderp?customerId=xxx
     * GET /api/orderp?region=EMEA
     */
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response getAllOrders(
            @QueryParam("customerId") String customerId,
            @QueryParam("region") String region,
            @QueryParam("offset") Integer offset,
            @QueryParam("limit") Integer limit) {
        logger.info("Fetching orders with filters - customerId: " + customerId + 
                   ", region: " + region + ", offset: " + offset + ", limit: " + limit);
        
        try {
            List<Order> orders;
            
            if (customerId != null && !customerId.isEmpty()) {
                orders = orderService.getOrdersByCustomerId(customerId);
            } else if (region != null && !region.isEmpty()) {
                orders = orderService.getOrdersByRegion(region);
            } else {
                orders = orderService.getAllOrders(offset, limit);
            }
            
            // Get total count for pagination metadata
            long totalCount = orderService.countOrders();
            
            return Response.ok(orders)
                .header("X-Pod-Name", System.getenv("HOSTNAME"))
                .header("X-Total-Count", String.valueOf(totalCount))
                .header("X-Returned-Count", String.valueOf(orders.size()))
                .header("X-Offset", offset != null ? String.valueOf(offset) : "0")
                .header("X-Limit", limit != null ? String.valueOf(limit) : "all")
                .build();
                
        } catch (Exception e) {
            logger.severe("Error fetching orders: " + e.getMessage());
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity("{\"error\": \"Failed to fetch orders: " + e.getMessage() + "\"}")
                .build();
        }
    }

    /**
     * Update an existing order
     * PUT /api/orderp/{orderId}
     */
    @PUT
    @Path("/{orderId}")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response updateOrder(@PathParam("orderId") String orderId, Order order) {
        logger.info("Updating order with ID: " + orderId);
        
        try {
            if (order == null) {
                return Response.status(Response.Status.BAD_REQUEST)
                    .entity("{\"error\": \"Order data is required\"}")
                    .build();
            }

            Order updatedOrder = orderService.updateOrder(orderId, order);
            
            if (updatedOrder == null) {
                return Response.status(Response.Status.NOT_FOUND)
                    .entity("{\"error\": \"Order not found with ID: " + orderId + "\"}")
                    .build();
            }
            
            return Response.ok(updatedOrder)
                .header("X-Pod-Name", System.getenv("HOSTNAME"))
                .build();
                
        } catch (Exception e) {
            logger.severe("Error updating order: " + e.getMessage());
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity("{\"error\": \"Failed to update order: " + e.getMessage() + "\"}")
                .build();
        }
    }

    /**
     * Delete an order
     * DELETE /api/orderp/{orderId}
     */
    @DELETE
    @Path("/{orderId}")
    @Produces(MediaType.APPLICATION_JSON)
    public Response deleteOrder(@PathParam("orderId") String orderId) {
        logger.info("Deleting order with ID: " + orderId);
        
        try {
            boolean deleted = orderService.deleteOrder(orderId);
            
            if (!deleted) {
                return Response.status(Response.Status.NOT_FOUND)
                    .entity("{\"error\": \"Order not found with ID: " + orderId + "\"}")
                    .build();
            }
            
            return Response.ok()
                .entity("{\"message\": \"Order deleted successfully\", \"id\": \"" + orderId + "\"}")
                .header("X-Pod-Name", System.getenv("HOSTNAME"))
                .build();
                
        } catch (Exception e) {
            logger.severe("Error deleting order: " + e.getMessage());
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity("{\"error\": \"Failed to delete order: " + e.getMessage() + "\"}")
                .build();
        }
    }

    /**
     * Get order count
     * GET /api/orderp/count
     */
    @GET
    @Path("/count")
    @Produces(MediaType.APPLICATION_JSON)
    public Response getOrderCount() {
        logger.info("Fetching order count");
        
        try {
            long count = orderService.countOrders();
            
            return Response.ok()
                .entity("{\"count\": " + count + "}")
                .header("X-Pod-Name", System.getenv("HOSTNAME"))
                .build();
                
        } catch (Exception e) {
            logger.severe("Error counting orders: " + e.getMessage());
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity("{\"error\": \"Failed to count orders: " + e.getMessage() + "\"}")
                .build();
        }
    }

    /**
     * Health check endpoint
     * GET /api/orderp/health
     */
    @GET
    @Path("/health")
    @Produces(MediaType.APPLICATION_JSON)
    public Response healthCheck() {
        return Response.ok()
            .entity("{\"status\": \"UP\", \"service\": \"OrderResourceP\"}")
            .header("X-Pod-Name", System.getenv("HOSTNAME"))
            .build();
    }
}
