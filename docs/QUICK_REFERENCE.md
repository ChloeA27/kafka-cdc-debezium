# Quick Reference — Debezium CDC




























































































































































`start.sh` deploys `config/avro/` by default. Swap to `config/json/` if you need to debug without Schema Registry.```    └── jdbc-sink.json         # Reference: JSON/String converters    ├── debezium-source.json   # Reference: JSON/String converters└── json/│   └── jdbc-sink.json         # Sink connector   (Avro converters)│   ├── debezium-source.json   # Source connector (Avro converters)├── avro/config/```## Config Layout---- **Schema evolution**: `auto.evolve: true` issues `ALTER TABLE` when the Avro schema adds a new column.- **Delete**: Debezium emits a tombstone (null payload) on DELETE; the sink issues a `DELETE FROM employees WHERE emp_id = ?`.- **Upsert**: `INSERT … ON CONFLICT (emp_id) DO UPDATE SET …` — idempotent replays.```"auto.create": "true""auto.evolve": "true","delete.enabled": "true","pk.fields": "emp_id","pk.mode": "record_value","insert.mode": "upsert",```json## JDBC Sink — Upsert + Schema Evolution---| `delete.retention.ms` | `100` | Tombstones are eligible for deletion quickly after consumer lag catches up. || `segment.bytes` | `10MB` | Small segments → more frequent compaction opportunities. || `min.cleanable.dirty.ratio` | `0.01` | Aggressive compaction — cleaner runs earlier. || `compression.type` | `snappy` | Fast compression with reasonable ratio, good for CDC event streams. || `cleanup.policy` | `compact` | Retains only the latest value per key (emp_id). Deleted rows produce a tombstone (null value); compaction eventually removes them. ||---|---|---|| Setting | Value | Reason |Topic `dbserver1.public.employees` is configured with:## Kafka Topic Configuration---**Key insight:** `kafka-schema-converter-7.6.0.jar` lives under `kafka-serde-tools/`, NOT alongside the other converter JARs — it was the final missing piece that caused `ClassNotFoundException: io/confluent/connect/schema/AbstractDataConfig`.| `common-utils-7.6.0.jar` | `/usr/share/java/confluent-common/` || `common-config-7.6.0.jar` | `/usr/share/java/confluent-common/` || `commons-compress-1.21.jar` | `/usr/share/java/kafka-serde-tools/` || `failureaccess-1.0.1.jar` | `/usr/share/java/kafka-serde-tools/` || `guava-32.0.1-jre.jar` | `/usr/share/java/kafka-serde-tools/` || `avro-1.11.3.jar` | `/usr/share/java/kafka-serde-tools/` || `kafka-schema-serializer-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` || `kafka-schema-converter-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` || `kafka-connect-avro-data-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` || `kafka-schema-registry-client-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` || `kafka-avro-serializer-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` || `kafka-connect-avro-converter-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` ||---|---|| JAR | Source path in cp-schema-registry |All JARs land in `/kafka/connect/confluentinc-kafka-connect-avro-converter/`:### JARs copied from `cp-schema-registry````FROM debezium/connect:2.5FROM confluentinc/cp-schema-registry:7.6.0 AS confluent-src```dockerfileUse a multi-stage Dockerfile. Stage 1 pulls `cp-schema-registry:7.6.0` (which ships with all Avro JARs pre-installed). Stage 2 is the Debezium base image — we copy only the required JARs.### SolutionThe Confluent Hub CDN (`d1i4a15mxbxib1.cloudfront.net`) is unreachable from Docker during build. Installing `confluentinc/kafka-connect-avro-converter` via `confluent-hub install` fails.### Problem## Custom Dockerfile (Multi-Stage Build)---- `dbserver1.public.employees-value`- `dbserver1.public.employees-key`The consumer calls Schema Registry with the 4-byte ID to retrieve the schema, then deserializes the payload. Schema Registry schemas:```[magic byte 0x00] [4-byte schema ID] [Avro binary payload]```Each Kafka message produced with `AvroConverter` has the format:### How Avro serialisation works| Compatibility checks | ❌ | ✅ Backward/Forward/Full || Schema evolution | Manual | Managed by Registry || Payload size | Larger (field names repeated) | Compact (binary, schema by reference) || Schema enforcement | ❌ No | ✅ Yes ||---|---|---|| | JSON | Avro |### Why Avro instead of JSON?## Avro + Schema Registry---- `KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:29093`- `KAFKA_NODE_ID=1`- `KAFKA_PROCESS_ROLES=broker,controller`Key config in `docker-compose.yml`:**Why:** Zookeeper adds operational complexity. KRaft is simpler to deploy for single-node setups and is the Kafka default since Kafka 3.x / Confluent 7.x.Kafka runs in KRaft (Raft-based) mode — the broker and controller are colocated on the same node.## KRaft Mode (No Zookeeper)---```Destination PostgreSQL (5438)        ▼        │ (JDBC Sink Connector) Kafka Connect Sink        ▼        │  (looked up per message via schema ID)  Avro schemas stored here Schema Registry (8081)        ▼        │        │  (log compaction + snappy)  Topic: dbserver1.public.employees  Kafka KRaft (29093)        ▼        │  Avro-encoded Kafka events        │ (Debezium 2.5) Kafka Connect Source        ▼        │  WAL (Write-Ahead Log) via pgoutput        │Source PostgreSQL (5437)```A Debezium CDC pipeline using Kafka KRaft, Avro + Schema Registry, and JDBC Sink.## Overview## Commands

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
