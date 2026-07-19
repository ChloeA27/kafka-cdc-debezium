# Debezium CDC — PostgreSQL to PostgreSQL with Avro & Schema Registry

Real-time Change Data Capture (CDC) pipeline using **Debezium 2.5**, **Kafka KRaft**, **Avro serialization**, and **Schema Registry** to replicate changes from a source PostgreSQL database to a destination PostgreSQL database.

## ✨ Features

| Feature | Details |
|---|---|
| **KRaft mode** | No Zookeeper — simpler, faster, production standard for 2026 |
| **Avro serialization** | Compact binary format — smaller on-wire messages than JSON (industry benchmark, not separately measured in this repo) |
| **Schema Registry** | Centralized schema management + type safety |
| **Log compaction** | Kafka topic retains only the latest state per key |
| **Snappy compression** | Reduces storage and network usage |
| **UPSERT + DELETE CDC** | Full INSERT / UPDATE / DELETE replication |

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        CDC PIPELINE (5 containers)                   │
└──────────────────────────────────────────────────────────────────────┘

  ┌─────────────────┐     WAL      ┌─────────────────┐
  │  Source DB      │ ──────────▶  │  Debezium       │
  │  PostgreSQL     │  pgoutput    │  Source         │
  │  Port: 5437     │              │  Connector      │
  └─────────────────┘              └────────┬────────┘
                                            │ Avro + Schema ID
                                            ▼
  ┌─────────────────┐            ┌──────────────────┐
  │  Schema         │◀──────────▶│  Kafka (KRaft)   │
  │  Registry       │  schema    │  Port: 29093     │
  │  Port: 8081     │  lookup    │  Topic: dbserver1│
  └─────────────────┘            │  .public         │
                                 │  .employees      │
                                 └────────┬─────────┘
                                          │ Avro + Schema ID
                                          ▼
                                 ┌─────────────────┐     SQL      ┌─────────────────┐
                                 │  Debezium JDBC  │ ──────────▶  │  Destination DB │
                                 │  Sink Connector │   UPSERT     │  PostgreSQL     │
                                 │  (Port: 8084)   │              │  Port: 5438     │
                                 └─────────────────┘              └─────────────────┘
```

### Data flow
1. App performs `INSERT` / `UPDATE` / `DELETE` on Source DB
2. PostgreSQL writes changes to WAL (Write-Ahead Log)
3. Debezium Source reads WAL via logical replication (`pgoutput`)
4. Source Connector **serializes** the event as **Avro** and registers the schema in Schema Registry
5. Event is published to Kafka topic with **log compaction + snappy compression**
6. Debezium JDBC Sink consumes the event, **deserializes** Avro using Schema Registry
7. Sink writes to Destination DB as `UPSERT` (or deletes on `DELETE` events)
8. Both databases in sync in **< 2 seconds**

## 🚀 Quick Start

```bash
bash start.sh   # start all 5 containers + deploy connectors
bash test.sh    # test INSERT / UPDATE / DELETE
bash stop.sh    # tear down
```

## 📁 Project Structure

```
kafka-cdc-debezium/
├── docker-compose.yml          # 5-container infrastructure
├── start.sh                    # One-command startup
├── stop.sh                     # Graceful shutdown
├── test.sh                     # End-to-end CDC tests
├── diagnose.sh                 # Health checks & troubleshooting
├── demo.sh                     # Live demo script
│
├── config/
│   ├── avro/                   # ✅ Active — Avro + Schema Registry
│   │   ├── debezium-source.json
│   │   └── jdbc-sink.json
│   └── json/                   # 📦 Reference — simpler JSON fallback
│       ├── debezium-source.json
│       └── jdbc-sink.json
│
├── docker/
│   └── connect/
│       └── Dockerfile          # Custom Connect image with Avro plugin
│                               # (multi-stage: copies JARs from cp-schema-registry:7.6.0)
│
├── sql/
│   └── setup_debezium.sql      # DB schema + seed data
│
└── docs/
    ├── ARCHITECTURE.md
    └── QUICK_REFERENCE.md
```

## 🐳 Containers

| Container | Image | Port | Role |
|---|---|---|---|
| `kafka-debezium` | `confluentinc/cp-kafka:7.6.0` | 29093 | Message broker (KRaft, no Zookeeper) |
| `schema-registry-debezium` | `confluentinc/cp-schema-registry:7.6.0` | 8081 | Avro schema store |
| `kafka-connect-debezium` | `debezium-connect-avro:2.5` (custom build) | 8084 | Runs source + sink connectors |
| `db-source-debezium` | `postgres:14.1-alpine` | 5437 | Source PostgreSQL |
| `db-dest-debezium` | `postgres:14.1-alpine` | 5438 | Destination PostgreSQL |

## ⚙️ Connector Configuration

### Source (`config/avro/debezium-source.json`)
- Reads `public.employees` via WAL / `pgoutput`
- Serializes with `AvroConverter` → Schema Registry at `http://schema-registry:8081`
- Topic: `dbserver1.public.employees` with log compaction + snappy compression

### Sink (`config/avro/jdbc-sink.json`)
- Listens to `dbserver1.public.employees`
- Deserializes with `AvroConverter` → Schema Registry
- `insert.mode: upsert`, primary key: `emp_id`
- `delete.enabled: true`, `schema.evolution: basic`

## 🗂️ Database Schema

```sql
CREATE TABLE employees (
    emp_id    SERIAL PRIMARY KEY,
    first_name VARCHAR(100),
    last_name  VARCHAR(100),
    dob        DATE,
    city       VARCHAR(100),
    salary     INT
);
```

## 🧪 Testing

`test.sh` validates the full pipeline:

```bash
bash test.sh
```

Covers:
- **DML** — `INSERT`, `UPDATE`, `DELETE` (synced to destination in < 2s)
- **DQL** — `SELECT`, aggregations (`COUNT`, `AVG`, `MAX`), `GROUP BY`, subqueries

Manual quick test:
```bash
# Insert into source
docker exec db-source-debezium psql -U postgres \
  -c "INSERT INTO employees(emp_id,first_name,last_name,dob,city,salary) VALUES (99,'Test','Avro','2000-01-01','Paris',99000);"

# Check destination (after ~2 seconds)
docker exec db-dest-debezium psql -U postgres \
  -c "SELECT * FROM employees WHERE emp_id=99;"
```

## 🔍 Monitoring

```bash
# Connector status
curl -s http://localhost:8084/connectors/postgres-source-connector/status | python3 -m json.tool
curl -s http://localhost:8084/connectors/postgres-sink-connector/status | python3 -m json.tool

# Avro schemas registered in Schema Registry
curl -s http://localhost:8081/subjects

# Kafka topics
docker exec kafka-debezium kafka-topics --list --bootstrap-server localhost:9092

# Full diagnostics
bash diagnose.sh
```

## 🐛 Troubleshooting

**Connectors RUNNING but no data in destination:**
```bash
bash diagnose.sh
```

**Need a clean restart:**
```bash
docker-compose down -v
bash start.sh
```

**Check Connect logs:**
```bash
docker logs kafka-connect-debezium --tail 50
```

**Manually redeploy connectors:**
```bash
curl -X DELETE http://localhost:8084/connectors/postgres-source-connector
curl -X DELETE http://localhost:8084/connectors/postgres-sink-connector
sleep 3
curl -X POST -H "Content-Type: application/json" --data @config/avro/debezium-source.json http://localhost:8084/connectors
curl -X POST -H "Content-Type: application/json" --data @config/avro/jdbc-sink.json http://localhost:8084/connectors
```

## 🔄 How Avro + Schema Registry Works

```
Producer side (Source Connector):
  1. Reads change from WAL
  2. Converts to Avro binary using the table schema
  3. Registers schema in Schema Registry → gets Schema ID (e.g. 1)
  4. Publishes: [magic byte][schema ID (4 bytes)][avro binary payload]

Consumer side (Sink Connector):
  1. Reads message from Kafka
  2. Extracts Schema ID from the first 5 bytes
  3. Fetches schema from Schema Registry by ID
  4. Deserializes Avro binary → typed Java object
  5. Builds and executes SQL UPSERT
```

**Schema Registry subjects created:**
- `dbserver1.public.employees-key` — schema for the message key (emp_id)
- `dbserver1.public.employees-value` — schema for the full row

## 🔁 Related Project — Iteration History

This is the second iteration of a CDC pipeline I built. The first,
[`kafka-cdc-project`](https://github.com/ChloeA27/kafka-cdc-project), used a
**hand-written, trigger-based** approach: a PostgreSQL trigger logged
changes into a shadow `emp_cdc` table, and custom Python `producer.py` /
`consumer.py` scripts polled that table and replayed changes to the
destination.

That version worked, but had real limitations this one addresses:

| | `kafka-cdc-project` (v1) | `kafka-cdc-debezium` (v2, this repo) |
|---|---|---|
| Change capture | Trigger writes to a shadow table, then polled | Reads the PostgreSQL WAL directly via logical replication (`pgoutput`) — no shadow table, no polling gap |
| Schema handling | Manual, hardcoded in Python | Avro + Schema Registry — centralized, type-safe, supports schema evolution |
| Moving parts | Custom producer/consumer scripts to maintain | Debezium connectors — configuration, not code |
| Message format | Raw JSON | Avro (compact binary, schema-enforced) |

Switching to log-based CDC (Debezium reading the WAL) removes the polling
latency and the shadow-table/trigger maintenance burden of the v1 design,
at the cost of more infrastructure to run (5 containers vs. Kafka + 2 DBs).

## 📚 References

- [Debezium Documentation](https://debezium.io/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html)
- [Apache Avro](https://avro.apache.org/docs/)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)

---

**Status**: ✅ Fully operational  
**Stack**: Debezium 2.5 · Kafka 7.6.0 KRaft · Avro · Schema Registry · PostgreSQL 14

