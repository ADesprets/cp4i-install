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
     */
    @Transactional
    public Order updateOrder(String id, OrderUpdateRequest updateRequest) {
        logger.info("Updating order with ID: " + id);
        
        OrderEntity entity = entityManager.find(OrderEntity.class, id);
        if (entity == null) {
            logger.warning("Order not found with ID: " + id);
            return null;
        }
        
        // Update only non-null fields
        if (updateRequest.getCustomerid() != null) {
            entity.setCustomerid(updateRequest.getCustomerid());
            logger.info("Updating customerid");
        }
        if (updateRequest.getCustomer() != null) {
            entity.setCustomer(updateRequest.getCustomer());
            logger.info("Updating customer");
        }
        if (updateRequest.getDescription() != null) {
            entity.setDescription(updateRequest.getDescription());
            logger.info("Updating description");
        }
        if (updateRequest.getPrice() != null) {
            entity.setPrice(updateRequest.getPrice());
            logger.info("Updating price");
        }
        if (updateRequest.getQuantity() != null) {
            entity.setQuantity(updateRequest.getQuantity());
            logger.info("Updating quantity");
        }
        if (updateRequest.getRegion() != null) {
            entity.setRegion(updateRequest.getRegion());
            logger.info("Updating region");
        }
        
        entityManager.merge(entity);
        entityManager.flush();
        
        logger.info("Order updated successfully");
        return entity.toOrder();
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
