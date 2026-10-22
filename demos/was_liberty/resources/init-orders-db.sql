-- ============================================
-- PostgreSQL Initialization Script for Orders Database
-- ============================================
-- This script creates the database, user, and schema
-- for the Order Management API with Persistence
-- ============================================

-- Create the orders table
CREATE TABLE IF NOT EXISTS orders (
    id VARCHAR(36) PRIMARY KEY,
    customerid VARCHAR(36) NOT NULL,
    customer VARCHAR(255) NOT NULL,
    description VARCHAR(500) NOT NULL,
    price DOUBLE PRECISION NOT NULL,
    quantity INTEGER NOT NULL,
    region VARCHAR(50) NOT NULL,
    ordertime TIMESTAMP NOT NULL
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_customerid ON orders(customerid);
CREATE INDEX IF NOT EXISTS idx_orders_region ON orders(region);
CREATE INDEX IF NOT EXISTS idx_orders_ordertime ON orders(ordertime DESC);

-- Insert sample data for testing
INSERT INTO orders (id, customerid, customer, description, price, quantity, region, ordertime)
VALUES 
    ('82a55abc-6c44-4e53-a4c6-03f6d2fb0c0a', '03c2ae4d-4d6e-4589-844b-e2a7a90803dd', 'Lottie Krajcik', 'S Navy Skinny Jeans', 22.81, 10, 'APAC', '2024-06-10 19:06:13.969'),
    ('f3b8c9d2-1a2b-4c5d-8e9f-0a1b2c3d4e5f', '12345678-1234-1234-1234-123456789012', 'John Doe', 'Laptop Computer', 1299.99, 1, 'EMEA', '2024-06-11 10:30:00.000'),
    ('a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d', '87654321-4321-4321-4321-210987654321', 'Jane Smith', 'Wireless Mouse', 29.99, 5, 'AMER', '2024-06-12 14:15:30.500')
ON CONFLICT (id) DO NOTHING;

-- Grant necessary permissions (if needed)
-- Note: Crunchy Operator handles user permissions automatically
-- GRANT ALL PRIVILEGES ON TABLE orders TO ordersuser;

-- Display table information
SELECT 'Orders table created successfully' AS status;
SELECT COUNT(*) AS initial_record_count FROM orders;
