# Quick Reference - Debezium CDC with KRaft

## 🚀 Start & Stop Commands

```bash
# Start everything
bash start.sh

# Test CDC (DQL + DML operations)
bash test.sh

# Troubleshoot
bash diagnose.sh

# Stop everything
bash stop.sh
```

## 📁 Project Files (8 total)

```
kafka-cdc-debezium/
├── docker-compose.yml              # Infrastructure (KRaft mode)
├── debezium-source-new.json        # Source connector
├── jdbc-sink-new.json              # Sink connector
├── setup_debezium.sql              # Database schema
├── start.sh                        # Start script
├── stop.sh                         # Stop script
├── test.sh                         # Test script
└── diagnose.sh                     # Diagnostic tool
```

## 🎯 Quick Test

```bash
# Manual INSERT test
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
INSERT INTO employees (first_name, last_name, dob, city, salary)
VALUES ('Alice', 'Test', '1990-01-01', 'NYC', 100000);
EOF

# Wait and check destination
sleep 2
docker exec -i db-dest-debezium psql -U postgres -d postgres \
  -c "SELECT * FROM employees WHERE first_name = 'Alice';"
```

## 📊 Architecture

```
Source DB (5437) → Debezium Source → Kafka KRaft (29093) → Debezium Sink → Destination DB (5438)
```

**4 Services:** Kafka (KRaft), Kafka Connect, Source DB, Destination DB  
**No Zookeeper!** 🚀

## ✅ Health Check

```bash
# Connector status
curl http://localhost:8084/connectors/postgres-source-connector/status
curl http://localhost:8084/connectors/postgres-sink-connector/status

# Database counts
docker exec db-source-debezium psql -U postgres -c "SELECT COUNT(*) FROM employees;"
docker exec db-dest-debezium psql -U postgres -c "SELECT COUNT(*) FROM employees;"
```

## 🔧 Common Operations

```bash
# Clean restart (removes all data)
docker-compose down -v
bash start.sh

# View logs
docker logs kafka-debezium
docker logs kafka-connect-debezium

# Access databases
docker exec -it db-source-debezium psql -U postgres -d postgres
docker exec -it db-dest-debezium psql -U postgres -d postgres
```
