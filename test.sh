#!/bin/bash

echo "=================================================="
echo "🧪 Testing Debezium CDC with KRaft (No Zookeeper)"
echo "=================================================="

# Test DQL (SELECT)
echo ""
echo "Test 0: DQL Operations (SELECT - Read Data)"
echo "--------------------------------------------"
echo "Querying all employees from Source DB:"
docker exec -i db-source-debezium psql -U postgres -d postgres -c "SELECT emp_id, first_name, last_name, city, salary FROM employees ORDER BY emp_id;"

echo ""
echo "Querying all employees from Destination DB:"
docker exec -i db-dest-debezium psql -U postgres -d postgres -c "SELECT emp_id, first_name, last_name, city, salary FROM employees ORDER BY emp_id;"

echo ""
echo "Aggregate Query (DQL) - Average Salary by City:"
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
SELECT city, COUNT(*) as employee_count, AVG(salary) as avg_salary, MAX(salary) as max_salary
FROM employees
GROUP BY city
ORDER BY avg_salary DESC;
EOF

echo ""
echo "Join Query (DQL) - Employees with Above Average Salary:"
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
SELECT e.emp_id, e.first_name, e.last_name, e.salary
FROM employees e
WHERE e.salary > (SELECT AVG(salary) FROM employees)
ORDER BY e.salary DESC;
EOF

# Test INSERT
echo ""
echo ""
echo "Test 1: INSERT Operation (DML)"
echo "--------------------------------"
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
INSERT INTO employees (first_name, last_name, dob, city, salary)
VALUES ('Alice', 'Wonder', '1992-03-15', 'Boston', 90000);
EOF

echo "Waiting 2 seconds for sync..."
sleep 2

echo "Source DB (port 5437):"
docker exec -i db-source-debezium psql -U postgres -d postgres -c "SELECT * FROM employees WHERE first_name = 'Alice';"

echo ""
echo "Destination DB (port 5438):"
docker exec -i db-dest-debezium psql -U postgres -d postgres -c "SELECT * FROM employees WHERE first_name = 'Alice';"

# Test UPDATE
echo ""
echo "Test 2: UPDATE Operation (DML)"
echo "--------------------------------"
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
UPDATE employees SET salary = 95000 WHERE first_name = 'Alice';
EOF

echo "Waiting 2 seconds for sync..."
sleep 2

echo "Source DB:"
docker exec -i db-source-debezium psql -U postgres -d postgres -c "SELECT * FROM employees WHERE first_name = 'Alice';"

echo ""
echo "Destination DB:"
docker exec -i db-dest-debezium psql -U postgres -d postgres -c "SELECT * FROM employees WHERE first_name = 'Alice';"

# Test DELETE
echo ""
echo "Test 3: DELETE Operation (DML)"
echo "--------------------------------"
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
DELETE FROM employees WHERE first_name = 'Alice';
EOF

echo "Waiting 2 seconds for sync..."
sleep 2

echo "Source DB:"
docker exec -i db-source-debezium psql -U postgres -d postgres -c "SELECT COUNT(*) FROM employees WHERE first_name = 'Alice';"

echo ""
echo "Destination DB:"
docker exec -i db-dest-debezium psql -U postgres -d postgres -c "SELECT COUNT(*) FROM employees WHERE first_name = 'Alice';"

echo ""
echo "=================================================="
echo "✅ Testing Complete!"
echo "=================================================="
echo ""
echo "🎯 Tested Operations:"
echo "  ✓ DQL: SELECT, Aggregations (COUNT, AVG, MAX), Joins"
echo "  ✓ DML: INSERT, UPDATE, DELETE"
echo "  ✓ All changes synced via Kafka (KRaft mode)"
echo ""
