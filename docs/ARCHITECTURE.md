# Architecture & Design Notes

## Overview

A Debezium CDC pipeline using Kafka KRaft, Avro + Schema Registry, and JDBC Sink.

```
Source PostgreSQL (5437)
        │
        │  WAL (Write-Ahead Log) via pgoutput
        ▼
 Kafka Connect Source
 (Debezium 2.5)
        │
        │  Avro-encoded Kafka events
        ▼
  Kafka KRaft (29093)
  Topic: dbserver1.public.employees
  (log compaction + snappy)
        │
        │
        ▼
 Schema Registry (8081)
  Avro schemas stored here
  (looked up per message via schema ID)
        │
        ▼
 Kafka Connect Sink
 (JDBC Sink Connector)
        │
        ▼
Destination PostgreSQL (5438)
```

---

## KRaft Mode (No Zookeeper)

Kafka runs in KRaft (Raft-based) mode — the broker and controller are colocated on the same node.

**Why:** Zookeeper adds operational complexity. KRaft is simpler to deploy for single-node setups and is the Kafka default since Kafka 3.x / Confluent 7.x.

Key config in `docker-compose.yml`:
- `KAFKA_PROCESS_ROLES=broker,controller`
- `KAFKA_NODE_ID=1`
- `KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:29093`

---

## Avro + Schema Registry

### Why Avro instead of JSON?

| | JSON | Avro |
|---|---|---|
| Schema enforcement | ❌ No | ✅ Yes |
| Payload size | Larger (field names repeated) | Compact (binary, schema by reference) |
| Schema evolution | Manual | Managed by Registry |
| Compatibility checks | ❌ | ✅ Backward/Forward/Full |

### How Avro serialisation works

Each Kafka message produced with `AvroConverter` has the format:

```
[magic byte 0x00] [4-byte schema ID] [Avro binary payload]
```

The consumer calls Schema Registry with the 4-byte ID to retrieve the schema, then deserializes the payload. Schema Registry schemas:
- `dbserver1.public.employees-key`
- `dbserver1.public.employees-value`

---

## Custom Dockerfile (Multi-Stage Build)

### Problem

The Confluent Hub CDN (`d1i4a15mxbxib1.cloudfront.net`) is unreachable from Docker during build. Installing `confluentinc/kafka-connect-avro-converter` via `confluent-hub install` fails.

### Solution

Use a multi-stage Dockerfile. Stage 1 pulls `cp-schema-registry:7.6.0` (which ships with all Avro JARs pre-installed). Stage 2 is the Debezium base image — we copy only the required JARs.

```dockerfile
FROM confluentinc/cp-schema-registry:7.6.0 AS confluent-src
FROM debezium/connect:2.5
```

### JARs copied from `cp-schema-registry`

All JARs land in `/kafka/connect/confluentinc-kafka-connect-avro-converter/`:

| JAR | Source path in cp-schema-registry |
|---|---|
| `kafka-connect-avro-converter-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` |
| `kafka-avro-serializer-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` |
| `kafka-schema-registry-client-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` |
| `kafka-connect-avro-data-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` |
| `kafka-schema-converter-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` |
| `kafka-schema-serializer-7.6.0.jar` | `/usr/share/java/kafka-serde-tools/` |
| `avro-1.11.3.jar` | `/usr/share/java/kafka-serde-tools/` |
| `guava-32.0.1-jre.jar` | `/usr/share/java/kafka-serde-tools/` |
| `failureaccess-1.0.1.jar` | `/usr/share/java/kafka-serde-tools/` |
| `commons-compress-1.21.jar` | `/usr/share/java/kafka-serde-tools/` |
| `common-config-7.6.0.jar` | `/usr/share/java/confluent-common/` |
| `common-utils-7.6.0.jar` | `/usr/share/java/confluent-common/` |

**Key insight:** `kafka-schema-converter-7.6.0.jar` lives under `kafka-serde-tools/`, NOT alongside the other converter JARs — it was the final missing piece that caused `ClassNotFoundException: io/confluent/connect/schema/AbstractDataConfig`.

---

## Kafka Topic Configuration

Topic `dbserver1.public.employees` is configured with:

| Setting | Value | Reason |
|---|---|---|
| `cleanup.policy` | `compact` | Retains only the latest value per key (emp_id). Deleted rows produce a tombstone (null value); compaction eventually removes them. |
| `compression.type` | `snappy` | Fast compression with reasonable ratio, good for CDC event streams. |
| `min.cleanable.dirty.ratio` | `0.01` | Aggressive compaction — cleaner runs earlier. |
| `segment.bytes` | `10MB` | Small segments → more frequent compaction opportunities. |
| `delete.retention.ms` | `100` | Tombstones are eligible for deletion quickly after consumer lag catches up. |

---

## JDBC Sink — Upsert + Schema Evolution

```json
"insert.mode": "upsert",
"pk.mode": "record_value",
"pk.fields": "emp_id",
"delete.enabled": "true",
"auto.evolve": "true",
"auto.create": "true"
```

- **Upsert**: `INSERT … ON CONFLICT (emp_id) DO UPDATE SET …` — idempotent replays.
- **Delete**: Debezium emits a tombstone (null payload) on DELETE; the sink issues a `DELETE FROM employees WHERE emp_id = ?`.
- **Schema evolution**: `auto.evolve: true` issues `ALTER TABLE` when the Avro schema adds a new column.

---

## Config Layout

```
config/
├── avro/
│   ├── debezium-source.json   # Source connector (Avro converters)
│   └── jdbc-sink.json         # Sink connector   (Avro converters)
└── json/
    ├── debezium-source.json   # Reference: JSON/String converters
    └── jdbc-sink.json         # Reference: JSON/String converters
```

`start.sh` deploys `config/avro/` by default. Swap to `config/json/` if you need to debug without Schema Registry.
