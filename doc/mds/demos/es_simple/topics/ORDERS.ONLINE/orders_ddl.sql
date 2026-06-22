-- ============================================================================
-- PostgreSQL DDL for ORDERS.ONLINE Avro Schema
-- Generated from: orders.online.avsc
-- Namespace: com.loosehangerjeans
-- ============================================================================

-- Drop tables if they exist (in reverse order of dependencies)
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS customer_emails CASCADE;


DROP TABLE IF EXISTS phones CASCADE;
DROP TABLE IF EXISTS addresses CASCADE;
DROP TABLE IF EXISTS countries CASCADE;

-- ============================================================================
-- CUSTOMERS TABLE
-- ============================================================================
CREATE TABLE customers (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE customers IS 'Customer information';
COMMENT ON COLUMN customers.id IS 'Unique id for the customer';
COMMENT ON COLUMN customers.name IS 'Name of the customer';

-- ============================================================================
-- CUSTOMER EMAILS TABLE (One-to-Many relationship)
-- ============================================================================
CREATE TABLE customer_emails (
    id SERIAL PRIMARY KEY,
    customer_id UUID NOT NULL,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
);

COMMENT ON TABLE customer_emails IS 'Email addresses for customers';
COMMENT ON COLUMN customer_emails.customer_id IS 'Reference to customer';
COMMENT ON COLUMN customer_emails.email IS 'Email address';

CREATE INDEX idx_customer_emails_customer_id ON customer_emails(customer_id);

-- ============================================================================
-- COUNTRIES TABLE
-- ============================================================================
CREATE TABLE countries (
    id SERIAL PRIMARY KEY,
    code CHAR(2) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE countries IS 'Countries for addresses';
COMMENT ON COLUMN countries.code IS 'Two-letter country code';
COMMENT ON COLUMN countries.name IS 'Name of the country';

-- ============================================================================
-- ADDRESSES TABLE
-- ============================================================================
CREATE TABLE addresses (
    id SERIAL PRIMARY KEY,
    number INTEGER,
    street VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    zipcode VARCHAR(20) NOT NULL,
    country_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (country_id) REFERENCES countries(id)
);

COMMENT ON TABLE addresses IS 'Shipping address information';
COMMENT ON COLUMN addresses.number IS 'House number for the shipping address';
COMMENT ON COLUMN addresses.street IS 'Street for the shipping address';
COMMENT ON COLUMN addresses.city IS 'City for the shipping address';
COMMENT ON COLUMN addresses.zipcode IS 'Zipcode for the shipping address';

CREATE INDEX idx_addresses_country_id ON addresses(country_id);

-- ============================================================================
-- ADDRESS PHONES TABLE
-- ============================================================================
CREATE TABLE phones (
    id SERIAL PRIMARY KEY,
    phone VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (address_id) REFERENCES addresses(id) ON DELETE CASCADE
);

COMMENT ON TABLE address_phones IS 'Phone numbers for shipping addresses';
COMMENT ON COLUMN address_phones.address_id IS 'Reference to shipping address';
COMMENT ON COLUMN address_phones.phone IS 'Phone number';

CREATE INDEX idx_address_phones_address_id ON address_phones(address_id);

-- ============================================================================
-- ORDERS TABLE (Main table)
-- ============================================================================
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    customer_id UUID NOT NULL,
    shipping_address_id INTEGER NOT NULL,
    billing_address_id INTEGER NOT NULL,
    ordertime TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (shipping_address_id) REFERENCES addresses(id),
    FOREIGN KEY (billing_address_id) REFERENCES addresses(id)
);

COMMENT ON TABLE orders IS 'Orders placed by customers';
COMMENT ON COLUMN orders.id IS 'Unique ID for the online order';
COMMENT ON COLUMN orders.customer_id IS 'Customer who made the online order';
COMMENT ON COLUMN orders.ordertime IS 'Time that the online order was made (UTC time in ISO 8601 format)';

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_shipping_address_id ON orders(shipping_address_id);
CREATE INDEX idx_orders_billing_address_id ON orders(billing_address_id);
CREATE INDEX idx_orders_ordertime ON orders(ordertime);

-- ============================================================================
-- PRODUCTS TABLE (One-to-Many relationship)
-- ============================================================================
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    order_id UUID NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

COMMENT ON TABLE products IS 'Products included in Orders';
COMMENT ON COLUMN products.order_id IS 'Reference to online order';
COMMENT ON COLUMN products.description IS 'Description of the ordered product';

CREATE INDEX idx_products_order_id ON products(order_id);

-- ============================================================================
-- VIEWS FOR EASIER QUERYING
-- ============================================================================

-- Complete order view with all related information
CREATE OR REPLACE VIEW v_complete_orders AS
SELECT 
    o.id AS order_id,
    o.ordertime,
    c.id AS customer_id,
    c.name AS customer_name,
    sa.number AS shipping_number,
    sa.street AS shipping_street,
    sa.city AS shipping_city,
    sa.zipcode AS shipping_zipcode,
    sc.code AS shipping_country_code,
    sc.name AS shipping_country_name,
    ba.number AS billing_number,
    ba.street AS billing_street,
    ba.city AS billing_city,
    ba.zipcode AS billing_zipcode,
    bc.code AS billing_country_code,
    bc.name AS billing_country_name
FROM orders o
JOIN customers c ON o.customer_id = c.id
JOIN addresses sa ON o.shipping_address_id = sa.id
JOIN shipping_countries sc ON sa.country_id = sc.id
JOIN addresses ba ON o.billing_address_id = ba.id
JOIN billing_countries bc ON ba.country_id = bc.id;

COMMENT ON VIEW v_complete_orders IS 'Complete view of orders with customer and address information';

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SAMPLE DATA (Optional - uncomment to insert)
-- ============================================================================

/*
-- Insert sample countries
INSERT INTO countries (code, name) VALUES 
    ('US', 'United States'),
    ('GB', 'United Kingdom'),
    ('FR', 'France'),
    ('DE', 'Germany');


-- Insert sample customer
INSERT INTO customers (id, name) VALUES 
    ('550e8400-e29b-41d4-a716-446655440000', 'John Doe');

INSERT INTO customer_emails (customer_id, email) VALUES 
    ('550e8400-e29b-41d4-a716-446655440000', 'john.doe@example.com'),
    ('550e8400-e29b-41d4-a716-446655440000', 'jdoe@work.com');

-- Insert sample addresses
INSERT INTO addresses (number, street, city, zipcode, country_id) VALUES 
    (123, 'Main Street', 'New York', '10001', 1);

INSERT INTO shipping_address_phones (shipping_address_id, phone) VALUES 
    (1, '+1-555-0100'),
    (1, '+1-555-0101');

INSERT INTO addresses (number, street, city, zipcode, country_id) VALUES 
    (123, 'Main Street', 'New York', '10001', 1);

INSERT INTO billing_address_phones (billing_address_id, phone) VALUES 
    (1, '+1-555-0100');

-- Insert sample order
INSERT INTO orders (id, customer_id, shipping_address_id, billing_address_id, ordertime) VALUES 
    ('660e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440000', 1, 1, '2026-06-03T13:00:00Z');

INSERT INTO products (order_id, description) VALUES 
    ('660e8400-e29b-41d4-a716-446655440000', 'Blue Jeans - Size 32'),
    ('660e8400-e29b-41d4-a716-446655440000', 'White T-Shirt - Size M');
*/

-- ============================================================================
-- GRANTS (Adjust as needed for your security requirements)
-- ============================================================================

-- Example: Grant permissions to a specific role
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- ============================================================================
-- END OF DDL
-- ============================================================================

-- Made with Bob
