# Debezium CDC — PostgreSQL to PostgreSQL with Avro & Schema Registry

Real-time Change Data Capture (CDC) pipeline using **Debezium 2.5**, **Kafka KRaft**, **Avro serialization**, and **Schema Registry** to replicate changes from a source PostgreSQL database to a destination PostgreSQL database.

## ✨ Features

| Feature | Details |
|---|---|
| **KRaft mode** | No Zookeeper — simpler, faster, production standard for 2026 |
| **Avro serialization** | 40–60% smaller messages vs JSON |
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
    ├── QUICK_REFERENCE.md
    ├── OPTIMIZATION_REPORT.md
    ├── OPTIMIZATION_HANDOUT.md
    └── MIGRATION_SUMMARY.md
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

## 📚 References

- [Debezium Documentation](https://debezium.io/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html)
- [Apache Avro](https://avro.apache.org/docs/)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)

---

**Status**: ✅ Fully operational  
**Last updated**: February 2026  
**Stack**: Debezium 2.5 · Kafka 7.6.0 KRaft · Avro · Schema Registry · PostgreSQL 14


Real-time Change Data Capture (CDC) pipeline using Debezium to replicate data from a source PostgreSQL database to a destination PostgreSQL database via Kafka **KRaft mode** (no Zookeeper!).

**🚀 Modern Kafka Architecture:**
- ✅ **KRaft Mode** - No Zookeeper required
- ✅ **4 Services** - Kafka, Kafka Connect, 2 PostgreSQL databases
- ✅ **Fast** - ~20 second startup
- ✅ **Simple** - Clean, easy-to-use scripts
- ✅ **Production Ready** - 2026 industry standard

## 🎯 Why This Stack?

### KRaft Benefits:
- **Simpler Architecture** - One less service to manage
- **Faster Startup** - Ready in ~20 seconds
- **Better Performance** - Lower latency, higher throughput
- **More Reliable** - No single point of failure
- **Future-Proof** - Official Kafka mode (Zookeeper deprecated)
- **Industry Standard** - Default for new projects in 2026

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CDC PIPELINE ARCHITECTURE                        │
└─────────────────────────────────────────────────────────────────────┘

  ┌──────────────────┐         ┌────────────────┐         ┌──────────────────┐
  │  Source DB       │         │  Kafka KRaft   │         │  Destination DB  │
  │  PostgreSQL      │         │  (No Zookeeper)│         │  PostgreSQL      │
  │                  │         │                │         │                  │
  │  Port: 5437      │         │  Port: 29093   │         │  Port: 5438      │
  │                  │         │                │         │                  │
  │  ┌────────────┐  │         │                │         │  ┌────────────┐  │
  │  │ employees  │  │         │                │         │  │ employees  │  │
  │  │  table     │  │         │                │         │  │  table     │  │
  │  └────────────┘  │         │                │         │  └────────────┘  │
  │        │         │         │                │         │        ▲         │
  └────────┼─────────┘         └────────────────┘         └────────┼─────────┘
           │                           │                            │
           │ WAL                       │                            │
           │                           │                            │
           ▼                           ▼                            │
  ┌─────────────────┐         ┌────────────────┐         ┌─────────────────┐
  │  Debezium       │ ──────▶ │  Kafka Topic   │ ──────▶ │  Debezium      │
  │  Source         │ produce │                │ consume │  JDBC Sink     │
  │  Connector      │         │  dbserver1     │         │  Connector     │
  │                 │         │  .public       │         │                │
  │  (reads WAL)    │         │  .employees    │         │  (writes rows) │
  └─────────────────┘         └────────────────┘         └─────────────────┘
           │                           │                            │
           └───────────────────────────┴────────────────────────────┘
                                       │
                              ┌────────▼─────────┐
                              │  Kafka Connect   │
                              │  (Port: 8084)    │
                              │                  │
                              │  Manages both    │
                              │  connectors      │
                              └──────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      DATA FLOW SEQUENCE                              │
└─────────────────────────────────────────────────────────────────────┘

1. Application performs INSERT/UPDATE/DELETE on Source DB
2. PostgreSQL writes changes to WAL (Write-Ahead Log)
3. Debezium Source Connector reads WAL via logical replication
4. Source Connector publishes change events to Kafka topic
5. Debezium JDBC Sink Connector consumes from Kafka topic
6. Sink Connector applies changes to Destination DB
7. Both databases stay in sync in real-time (< 2 seconds)
```

## 🚀 Quick Start

```bash
# Start the CDC pipeline
bash start.sh

# Test all operations (DQL + DML)
bash test.sh

# Stop the pipeline
bash stop.sh
```

That's it! Three simple commands. 🎉

## 📁 Project Files (12 total)

### **Core Configuration (4 files):**

1. **docker-compose.yml** - KRaft infrastructure (no Zookeeper!)
   - Kafka in KRaft mode
   - Kafka Connect
   - Source PostgreSQL (5437)
   - Destination PostgreSQL (5438)
   
2. **debezium-source-new.json** - Source connector configuration
   - Reads PostgreSQL WAL
   - Publishes to Kafka
   
3. **jdbc-sink-new.json** - Sink connector configuration
   - Consumes from Kafka
   - Writes to destination PostgreSQL
   
4. **setup_debezium.sql** - Database initialization
   - Creates employees table
   - Inserts test data

### **Scripts (4 files):**

5. **start.sh** - Complete startup automation
6. **stop.sh** - Graceful shutdown
7. **test.sh** - Tests all operations (DQL + DML)
8. **diagnose.sh** - Troubleshooting and health checks

### **Documentation (4 files):**

9. **README.md** - This complete guide
10. **QUICK_REFERENCE.md** - Fast command reference
11. **MIGRATION_SUMMARY.md** - KRaft migration details
12. **BUGFIX_SUMMARY.md** - Bug fix history

## 🧪 What Gets Tested

The `test.sh` script validates both **DQL** and **DML** operations:

### DQL (Data Query Language):
- ✅ **SELECT** - Basic queries
- ✅ **Aggregations** - COUNT, AVG, MAX, GROUP BY
- ✅ **Joins** - Subqueries and complex queries
- ✅ **Filtering** - WHERE clauses

### DML (Data Manipulation Language):
- ✅ **INSERT** - Create new records
- ✅ **UPDATE** - Modify existing records
- ✅ **DELETE** - Remove records

All changes sync to destination database within ~2 seconds!

## 🗂️ Database Schema

```sql
CREATE TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    dob DATE,
    city VARCHAR(100),
    salary INT
);
```

## 🔌 Port Mapping

| Service | Internal Port | Host Port | Description |
|---------|--------------|-----------|-------------|
| Kafka (KRaft) | 9092 | 29093 | Message broker |
| Kafka Connect | 8083 | 8084 | Connector runtime |
| Source DB | 5432 | 5437 | PostgreSQL source |
| Destination DB | 5432 | 5438 | PostgreSQL destination |

## 📝 Configuration Details

### Source Connector Features:
- **WAL Reading**: Uses PostgreSQL logical replication (`pgoutput`)
- **Snapshot Mode**: `always` - captures existing data on start
- **Schema**: Includes full schema information for type safety
- **Heartbeat**: 10-second intervals to keep connection alive

### Sink Connector Features:
- **Insert Mode**: `upsert` - updates if exists, inserts if new
- **Primary Key**: Uses `emp_id` from record key
- **Delete Support**: Enabled - removes records on DELETE events
- **Schema Evolution**: `basic` - automatically adapts to schema changes
- **Table Mapping**: Writes to `employees` table

## 🔧 Manual Operations

### Start Services

```bash
docker-compose up -d
sleep 30  # Wait for services
```

### Initialize Databases

```bash
# Source DB
docker exec -i db-source-debezium psql -U postgres -d postgres < setup_debezium.sql

# Destination DB  
docker exec -i db-dest-debezium psql -U postgres -d postgres < setup_debezium.sql
```

### Create Connectors

```bash
# Source connector
curl -X POST -H "Content-Type: application/json" \
  --data @debezium-source-new.json \
  http://localhost:8084/connectors

# Sink connector (wait 5 seconds after source)
sleep 5
curl -X POST -H "Content-Type: application/json" \
  --data @jdbc-sink-new.json \
  http://localhost:8084/connectors
```

### Verify Setup

```bash
bash diagnose.sh
```

## 🔍 Monitoring & Diagnostics

### Check Connector Status

```bash
# Source connector
curl http://localhost:8084/connectors/postgres-source-connector/status | jq

# Sink connector
curl http://localhost:8084/connectors/postgres-sink-connector/status | jq
```

### Check Kafka Topics

```bash
docker exec kafka-debezium kafka-topics --list --bootstrap-server localhost:9092
```

### View Messages in Kafka

```bash
docker exec kafka-debezium kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.employees \
  --from-beginning \
  --max-messages 5
```

### Compare Databases

```bash
# Source
docker exec db-source-debezium psql -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM employees;"

# Destination
docker exec db-dest-debezium psql -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM employees;"
```

### Run Full Diagnostics

```bash
bash diagnose.sh
```

## 🧪 Manual Testing

### Test INSERT

```bash
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
INSERT INTO employees (first_name, last_name, dob, city, salary)
VALUES ('Alice', 'Wonder', '1992-03-15', 'Boston', 90000);
EOF

# Wait and check destination
sleep 2
docker exec db-dest-debezium psql -U postgres -d postgres \
  -c "SELECT * FROM employees WHERE first_name = 'Alice';"
```

### Test UPDATE

```bash
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
UPDATE employees SET salary = 95000 WHERE first_name = 'Alice';
EOF

# Wait and check
sleep 2
docker exec db-dest-debezium psql -U postgres -d postgres \
  -c "SELECT * FROM employees WHERE first_name = 'Alice';"
```

### Test DELETE

```bash
docker exec -i db-source-debezium psql -U postgres -d postgres << 'EOF'
DELETE FROM employees WHERE first_name = 'Alice';
EOF

# Wait and check
sleep 2
docker exec db-dest-debezium psql -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM employees WHERE first_name = 'Alice';"
```

## 🐛 Troubleshooting

### Issue: Connectors show RUNNING but no data flows

**Solution:** Run diagnostics to identify the issue
```bash
bash diagnose.sh
```

### Issue: Destination DB is empty

**Solution:** Restart connectors to trigger initial snapshot
```bash
curl -X DELETE http://localhost:8084/connectors/postgres-source-connector
curl -X DELETE http://localhost:8084/connectors/postgres-sink-connector
sleep 5
curl -X POST -H "Content-Type: application/json" --data @debezium-source-new.json http://localhost:8084/connectors
curl -X POST -H "Content-Type: application/json" --data @jdbc-sink-new.json http://localhost:8084/connectors
```

### Issue: Port already in use

**Solution:** Stop conflicting services or change ports in docker-compose.yml

### Issue: Connectors fail to start

**Solution:** Check logs
```bash
docker logs kafka-connect-debezium --tail 50
```

### Issue: Clean slate needed

**Solution:** Remove all data and restart
```bash
docker-compose down -v
bash start.sh
```

## 🔄 How CDC Works

1. **Write-Ahead Log (WAL)**: PostgreSQL records all changes to WAL before applying them
2. **Logical Replication**: Debezium creates a replication slot to read WAL
3. **Change Events**: Each INSERT/UPDATE/DELETE becomes a Kafka message
4. **Event Format**: 
   ```json
   {
     "before": { /* old values */ },
     "after": { /* new values */ },
     "op": "c|u|d|r",  // create, update, delete, read
     "source": { /* metadata */ }
   }
   ```
5. **Sink Processing**: JDBC Sink applies changes to destination based on `op` field

## 🎯 Use Cases

- **Database Replication**: Keep read replicas in sync
- **Data Migration**: Move data between databases with zero downtime
- **Analytics Pipeline**: Stream changes to data warehouse
- **Audit Trail**: Track all database changes
- **Microservices**: Propagate data changes across services
- **Cache Invalidation**: Update caches when source data changes
- **Event Sourcing**: Build event-driven architectures

## 📚 Additional Resources

- [Debezium Documentation](https://debezium.io/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- [Confluent Platform](https://docs.confluent.io/platform/current/installation/overview.html)

## 🤝 Contributing

This is a learning/production-ready project. Feel free to:
- Add more tables to the schema
- Implement data transformations
- Add monitoring dashboards
- Create additional test scenarios
- Extend to other databases

## 📄 License

This project is for educational and production purposes.

---

**Project Status**: ✅ Production Ready (KRaft Mode)

**Last Updated**: February 13, 2026

**Key Achievement**: Modern CDC pipeline with KRaft mode - simpler, faster, and more reliable than traditional Zookeeper-based setups!
