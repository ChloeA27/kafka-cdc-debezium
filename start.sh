#!/bin/bash

echo "=================================================="
echo "🚀 Starting Debezium CDC with KRaft (No Zookeeper)"
echo "=================================================="
echo ""
echo "📌 Port Mapping:"
echo "  Kafka (KRaft):    29093"
echo "  Kafka Connect:    8084"
echo "  Source DB:        5437"
echo "  Destination DB:   5438"
echo "=================================================="

# 1. Start Docker services
echo ""
echo "Step 1: Starting Docker services with KRaft (building Avro plugin if needed)..."
docker-compose up -d --build

# Wait for services to be ready
echo ""
echo "Waiting for services to start (30 seconds)..."
sleep 30

# 2. Initialize Source Database
echo ""
echo "Step 2: Initializing Source Database (port 5437)..."
docker exec -i db-source-debezium psql -U postgres -d postgres < sql/setup_debezium.sql

# 3. Initialize Destination Database
echo ""
echo "Step 3: Initializing Destination Database (port 5438)..."
docker exec -i db-dest-debezium psql -U postgres -d postgres << 'EOF'
CREATE TABLE IF NOT EXISTS employees(
    emp_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    dob DATE,
    city VARCHAR(100),
    salary INT
);
SELECT 'Destination DB initialized' AS status;
EOF

# 4. Wait for Kafka Connect to be ready
echo ""
echo "Step 4: Waiting for Kafka Connect to be ready..."
until curl -s http://localhost:8084/ > /dev/null; do
    echo "Waiting for Kafka Connect..."
    sleep 5
done

echo ""
echo "Step 5: Creating Debezium Source Connector (Avro + Log Compaction)..."
curl -X POST -H "Content-Type: application/json" \
  --data @config/avro/debezium-source.json \
  http://localhost:8084/connectors

echo ""
echo ""
echo "Step 6: Creating JDBC Sink Connector (Avro)..."
sleep 5
curl -X POST -H "Content-Type: application/json" \
  --data @config/avro/jdbc-sink.json \
  http://localhost:8084/connectors

echo ""
echo ""
echo "Step 7: Waiting for connectors to start (10 seconds)..."
sleep 10

# 8. Verify setup
echo ""
echo "Step 8: Verifying Setup..."
echo ""
echo "Source Connector Status:"
curl -s http://localhost:8084/connectors/postgres-source-connector/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8084/connectors/postgres-source-connector/status

echo ""
echo ""
echo "Sink Connector Status:"
curl -s http://localhost:8084/connectors/postgres-sink-connector/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8084/connectors/postgres-sink-connector/status

echo ""
echo ""
echo "=================================================="
echo "✅ Debezium CDC with KRaft is ready!"
echo "=================================================="
echo ""
echo "🎯 Optimizations Enabled:"
echo "  ✓ No Zookeeper (KRaft mode)"
echo "  ✓ Avro format (40-60% smaller than JSON)"
echo "  ✓ Schema Registry (type safety + evolution)"
echo "  ✓ Log compaction (keeps only latest state)"
echo "  ✓ Compression (snappy)"
echo ""
echo "Next steps:"
echo "  • Test CDC: bash test.sh"
echo "  • Diagnose: bash diagnose.sh"
echo "  • Stop: bash stop.sh"
echo ""
