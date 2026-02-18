# Custom Kafka Connect image with Confluent Avro Converter
# Multi-stage build: copies JARs directly from the official Confluent Schema Registry
# image (same 7.6.0 version) — no internet downloads, no dependency guessing.

# Stage 1: Confluent Schema Registry image (source of Avro converter JARs)
FROM confluentinc/cp-schema-registry:7.6.0 AS confluent-src

# Stage 2: Final image based on Debezium Connect
FROM debezium/connect:2.5

USER root

ENV PLUGIN_DIR=/kafka/connect/confluentinc-kafka-connect-avro-converter
RUN mkdir -p ${PLUGIN_DIR}

# Copy the complete, tested set of Avro converter JARs from the Confluent image.
# These are the exact versions Confluent packages together — no missing dependencies.
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/avro-1.11.3.jar               ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/kafka-avro-serializer-7.6.0.jar          ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/kafka-connect-avro-converter-7.6.0.jar   ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/kafka-connect-avro-data-7.6.0.jar        ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/kafka-schema-converter-7.6.0.jar         ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/kafka-schema-registry-client-7.6.0.jar   ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/kafka-schema-serializer-7.6.0.jar        ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/guava-32.0.1-jre.jar                     ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/failureaccess-1.0.1.jar                  ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/kafka-serde-tools/commons-compress-1.21.jar                ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/confluent-common/common-config-7.6.0.jar                   ${PLUGIN_DIR}/
COPY --from=confluent-src /usr/share/java/confluent-common/common-utils-7.6.0.jar                    ${PLUGIN_DIR}/

# Switch back to non-root user (Debezium default)
USER 1001
