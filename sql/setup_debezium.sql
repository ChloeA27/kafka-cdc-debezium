-- ================================================
-- Simplified Setup Script for Debezium CDC Project
-- Run this on BOTH databases (source and destination)
-- ================================================

-- Create employees table (business table)
CREATE TABLE IF NOT EXISTS employees(
    emp_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    dob DATE,
    city VARCHAR(100),
    salary INT
);

-- ================================================
-- IMPORTANT: No CDC table needed!
-- IMPORTANT: No triggers needed!
-- Debezium captures changes directly from PostgreSQL WAL
-- ================================================

-- Insert some test data
INSERT INTO employees (first_name, last_name, dob, city, salary)
VALUES 
    ('John', 'Doe', '1990-01-15', 'Boston', 75000),
    ('Jane', 'Smith', '1985-06-20', 'New York', 85000),
    ('Bob', 'Johnson', '1992-03-10', 'Chicago', 65000);

SELECT 'Setup completed successfully!' AS status;
SELECT * FROM employees;
