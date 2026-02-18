# Quick Reference — Debezium CDC

## Commands

```bash
bash start.sh       # Start all 5 containers + deploy connectors (~30s)
bash test.sh        # Run INSERT / UPDATE / DELETE tests
bash diagnose.sh    # Health checks + connector status
bash stop.sh        # Tear down all containers
```

## Ports

| Service | Host Port |
|---|---|
| Kafka (KRaft) | 29093 |
| Schema Registry | 8081 |
| Kafka Connect | 8084 |
| Source DB | 5437 |
| Destination DB | 5438 |

## Connector Status

```bash
curl -s http://localhost:8084/connectors/postgres-source-connector/status | python3 -m json.tool
curl -s http://localhost:8084/connectors/postgres-sink-connector/status | python3 -m json.tool
```

## Avro Schemas (Schema Registry)

```bash
curl -s http://localhost:8081/subjects
# ["dbserver1.public.employees-key", "dbserver1.public.employees-value"]
```

## Kafka Topics

```bash
docker exec kafka-debezium kafka-topics --list --bootstrap-server localhost:9092
```

## Quick Manual Test

```bash
# Write to source
docker exec db-source-debezium psql -U postgres \
  -c "INSERT INTO employees(emp_id,first_name,last_name,dob,city,salary) VALUES (99,'Quick','Test','2000-01-01','NYC',80000) ON CONFLICT DO NOTHING;"

# Check destination after ~2 seconds
sleep 2
docker exec db-dest-debezium psql -U postgres -c "SELECT * FROM employees WHERE emp_id=99;"
```

## DB Row Counts (Sync Check)

```bash
docker exec db-source-debezium psql -U postgres -c "SELECT COUNT(*) FROM employees;"
docker exec db-dest-debezium psql -U postgres -c "SELECT COUNT(*) FROM employees;"
```

## Redeploy Connectors (without full restart)

```bash
curl -X DELETE http://localhost:8084/connectors/postgres-source-connector
curl -X DELETE http://localhost:8084/connectors/postgres-sink-connector
sleep 3
curl -X POST -H "Content-Type: application/json" \
  --data @config/avro/debezium-source.json http://localhost:8084/connectors
curl -X POST -H "Content-Type: application/json" \
  --data @config/avro/jdbc-sink.json http://localhost:8084/connectors
```

## Clean Restart (wipes all data)

```bash
docker-compose down -v && bash start.sh
```

## Logs

```bash
docker logs kafka-connect-debezium --tail 50
docker logs kafka-debezium --tail 20
```
