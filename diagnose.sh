#!/bin/bash

echo "=================================================="
echo "🔍 Diagnosing CDC Sync Issues"
echo "=================================================="

# 1. Check Source Connector Status
echo ""
echo "1️⃣ Source Connector Status:"
echo "----------------------------"
curl -s http://localhost:8084/connectors/postgres-source-connector/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8084/connectors/postgres-source-connector/status

# 2. Check Sink Connector Status
echo ""
echo ""
echo "2️⃣ Sink Connector Status:"
echo "----------------------------"
curl -s http://localhost:8084/connectors/postgres-sink-connector/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8084/connectors/postgres-sink-connector/status

# 3. Check Kafka Topics
echo ""
echo ""
echo "3️⃣ Kafka Topics:"
echo "----------------------------"
docker exec kafka-debezium kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | grep -E "(dbserver|employee)"

# 4. Check if there are messages in the topic
echo ""
echo ""
echo "4️⃣ Messages in Kafka Topic (first 5):"
echo "----------------------------"
timeout 5 docker exec kafka-debezium kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.employees \
  --from-beginning \
  --max-messages 5 2>/dev/null || echo "No messages found or timeout"

# 5. Compare databases
echo ""
echo ""
echo "5️⃣ Database Comparison:"
echo "----------------------------"
SOURCE_COUNT=$(docker exec -i db-source-debezium psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM employees;" 2>/dev/null | tr -d ' ')
DEST_COUNT=$(docker exec -i db-dest-debezium psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM employees;" 2>/dev/null | tr -d ' ')

echo "Source DB rows: $SOURCE_COUNT"
echo "Destination DB rows: $DEST_COUNT"

if [ "$SOURCE_COUNT" = "$DEST_COUNT" ]; then
    echo "✅ Row counts match!"
else
    echo "❌ Row counts DO NOT match!"
    echo ""
    echo "Source DB data:"
    docker exec -i db-source-debezium psql -U postgres -d postgres -c "SELECT * FROM employees;"
    echo ""
    echo "Destination DB data:"
    docker exec -i db-dest-debezium psql -U postgres -d postgres -c "SELECT * FROM employees;"
fi

# 6. Check Kafka Connect logs for errors
echo ""
echo ""
echo "6️⃣ Recent Kafka Connect Logs (last 30 lines):"
echo "----------------------------"
docker logs kafka-connect-debezium --tail 30 2>&1 | grep -E "(ERROR|WARN|exception|Exception)" || echo "No errors found in recent logs"

echo ""
echo "=================================================="
echo "🔧 Diagnosis Complete!"
echo "=================================================="
echo ""
echo "If Kafka topic has no messages, the Source Connector may need to be reset."
echo "Run: ./reset_and_restart.sh"
echo ""
