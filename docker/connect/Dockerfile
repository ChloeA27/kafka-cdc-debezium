# Custom Kafka Connect image with Confluent Avro Converter
# Extends official Debezium Connect 2.5 and adds Avro plugin

FROM debezium/connect:2.5

USER root

# Install dependencies needed to download and extract the plugin
RUN microdnf install -y curl unzip && microdnf clean all

# Download and install Confluent Avro Converter plugin from Confluent Hub
RUN curl -L -o /tmp/avro-converter.zip \
    "https://d1i4a15mxbxib1.cloudfront.net/api/plugins/confluentinc/kafka-connect-avro-converter/versions/7.6.0/confluentinc-kafka-connect-avro-converter-7.6.0.zip" && \
    mkdir -p /kafka/connect/confluentinc-kafka-connect-avro-converter && \
    cd /tmp && unzip avro-converter.zip && \
    cp confluentinc-kafka-connect-avro-converter-7.6.0/lib/*.jar \
       /kafka/connect/confluentinc-kafka-connect-avro-converter/ && \
    rm -rf /tmp/avro-converter.zip /tmp/confluentinc-kafka-connect-avro-converter-7.6.0

# Switch back to non-root user (Debezium default)
USER 1001
