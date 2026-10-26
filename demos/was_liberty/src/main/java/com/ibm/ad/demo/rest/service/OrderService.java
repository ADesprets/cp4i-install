package com.ibm.ad.demo.rest.service;

import com.ibm.ad.demo.rest.data.Order;
import com.ibm.ad.demo.rest.data.OrderEntity;
import com.ibm.ad.demo.rest.data.OrderUpdateRequest;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.persistence.TypedQuery;
import jakarta.transaction.Transactional;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.logging.Logger;

@ApplicationScoped
public class OrderService {

    private static final Logger logger = Logger.getLogger(OrderService.class.getName());

    @PersistenceContext(unitName = "ordersPU")
    private EntityManager entityManager;

    /**
     * Create a new order
     */
    @Transactional
    public Order createOrder(Order order) {
        logger.info("Creating new order");
        
        // Generate ID if not provided
        if (order.getId() == null || order.getId().isEmpty()) {
            order.id = UUID.randomUUID().toString();
        }
        
        // Set ordertime if not provided
        if (order.getOrdertime() == null || order.getOrdertime().isEmpty()) {
            order.ordertime = LocalDateTime.now().toString();
        }
        
        OrderEntity entity = OrderEntity.fromOrder(order);
        entityManager.persist(entity);
        entityManager.flush();
        
        logger.info("Order created with ID: " + entity.getId());
        return entity.toOrder();
    }

    /**
     * Get order by ID
     */
    public Order getOrderById(String id) {
        logger.info("Fetching order with ID: " + id);
        
        OrderEntity entity = entityManager.find(OrderEntity.class, id);
        if (entity == null) {
            logger.warning("Order not found with ID: " + id);
            return null;
        }
        
        return entity.toOrder();
    }

    /**
     * Get all orders with pagination
     */
    public List<Order> getAllOrders(Integer offset, Integer limit) {
        logger.info("Fetching all orders with offset=" + offset + ", limit=" + limit);
        
        TypedQuery<OrderEntity> query = entityManager.createNamedQuery("OrderEntity.findAll", OrderEntity.class);
        
        // Apply pagination if parameters are provided
        if (offset != null && offset >= 0) {
            query.setFirstResult(offset);
        }
        if (limit != null && limit > 0) {
            query.setMaxResults(limit);
        }
        
        List<OrderEntity> entities = query.getResultList();
        
        logger.info("Found " + entities.size() + " orders");
        return entities.stream()
                .map(OrderEntity::toOrder)
                .collect(Collectors.toList());
    }

    /**
     * Get orders by customer ID
     */
    public List<Order> getOrdersByCustomerId(String customerId) {
        logger.info("Fetching orders for customer ID: " + customerId);
        
        TypedQuery<OrderEntity> query = entityManager.createNamedQuery("OrderEntity.findByCustomerId", OrderEntity.class);
        query.setParameter("customerid", customerId);
        List<OrderEntity> entities = query.getResultList();
        
        logger.info("Found " + entities.size() + " orders for customer");
        return entities.stream()
                .map(OrderEntity::toOrder)
                .collect(Collectors.toList());
    }

    /**
     * Get orders by region
     */
    public List<Order> getOrdersByRegion(String region) {
        logger.info("Fetching orders for region: " + region);
        
        TypedQuery<OrderEntity> query = entityManager.createNamedQuery("OrderEntity.findByRegion", OrderEntity.class);
        query.setParameter("region", region);
        List<OrderEntity> entities = query.getResultList();
        
        logger.info("Found " + entities.size() + " orders for region");
        return entities.stream()
                .map(OrderEntity::toOrder)
                .collect(Collectors.toList());
    }

    /**
     * Update an existing order (partial update)
     * Only updates fields that are non-null in the updateRequest
     * Uses dynamic JPQL to update only the provided fields
     */
    @Transactional
    public Order updateOrder(String id, OrderUpdateRequest updateRequest) {
        logger.info("Updating order with ID: " + id);
        
        // First verify the order exists
        OrderEntity entity = entityManager.find(OrderEntity.class, id);
        if (entity == null) {
            logger.warning("Order not found with ID: " + id);
            return null;
        }
        
        // Build dynamic UPDATE query with only non-null fields
        StringBuilder jpql = new StringBuilder("UPDATE OrderEntity o SET ");
        boolean first = true;
        
        if (updateRequest.getCustomerid() != null) {
            if (!first) jpql.append(", ");
            jpql.append("o.customerid = :customerid");
            first = false;
            logger.info("Updating customerid to: " + updateRequest.getCustomerid());
        }
        if (updateRequest.getCustomer() != null) {
            if (!first) jpql.append(", ");
            jpql.append("o.customer = :customer");
            first = false;
            logger.info("Updating customer to: " + updateRequest.getCustomer());
        }
        if (updateRequest.getDescription() != null) {
            if (!first) jpql.append(", ");
            jpql.append("o.description = :description");
            first = false;
            logger.info("Updating description to: " + updateRequest.getDescription());
        }
        if (updateRequest.getPrice() != null) {
            if (!first) jpql.append(", ");
            jpql.append("o.price = :price");
            first = false;
            logger.info("Updating price to: " + updateRequest.getPrice());
        }
        if (updateRequest.getQuantity() != null) {
            if (!first) jpql.append(", ");
            jpql.append("o.quantity = :quantity");
            first = false;
            logger.info("Updating quantity to: " + updateRequest.getQuantity());
        }
        if (updateRequest.getRegion() != null) {
            if (!first) jpql.append(", ");
            jpql.append("o.region = :region");
            first = false;
            logger.info("Updating region to: " + updateRequest.getRegion());
        }
        
        jpql.append(" WHERE o.id = :id");
        
        // Create and execute the update query
        var query = entityManager.createQuery(jpql.toString());
        
        // Set parameters for non-null fields
        if (updateRequest.getCustomerid() != null) {
            query.setParameter("customerid", updateRequest.getCustomerid());
        }
        if (updateRequest.getCustomer() != null) {
            query.setParameter("customer", updateRequest.getCustomer());
        }
        if (updateRequest.getDescription() != null) {
            query.setParameter("description", updateRequest.getDescription());
        }
        if (updateRequest.getPrice() != null) {
            query.setParameter("price", updateRequest.getPrice());
        }
        if (updateRequest.getQuantity() != null) {
            query.setParameter("quantity", updateRequest.getQuantity());
        }
        if (updateRequest.getRegion() != null) {
            query.setParameter("region", updateRequest.getRegion());
        }
        query.setParameter("id", id);
        
        int updatedCount = query.executeUpdate();
        logger.info("Updated " + updatedCount + " order(s)");
        
        // Refresh and return the updated entity
        entityManager.clear(); // Clear persistence context to force reload
        OrderEntity updatedEntity = entityManager.find(OrderEntity.class, id);
        
        logger.info("Order updated successfully");
        return updatedEntity.toOrder();
    }

    /**
     * Delete an order
     */
    @Transactional
    public boolean deleteOrder(String id) {
        logger.info("Deleting order with ID: " + id);
        
        OrderEntity entity = entityManager.find(OrderEntity.class, id);
        if (entity == null) {
            logger.warning("Order not found with ID: " + id);
            return false;
        }
        
        entityManager.remove(entity);
        entityManager.flush();
        
        logger.info("Order deleted successfully");
        return true;
    }

    /**
     * Count total orders
     */
    public long countOrders() {
        logger.info("Counting total orders");
        
        TypedQuery<Long> query = entityManager.createQuery(
            "SELECT COUNT(o) FROM OrderEntity o", Long.class);
        Long count = query.getSingleResult();
        
        logger.info("Total orders: " + count);
        return count;
    }
}
