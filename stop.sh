#!/bin/bash

echo "=================================================="
echo "🛑 Stopping Debezium CDC (KRaft Mode)"
echo "=================================================="

# Delete connectors first
echo ""
echo "Deleting connectors..."
curl -X DELETE http://localhost:8084/connectors/postgres-source-connector 2>/dev/null
curl -X DELETE http://localhost:8084/connectors/postgres-sink-connector 2>/dev/null

# Stop services
echo ""
echo "Stopping Docker services..."
docker-compose down

echo ""
echo "=================================================="
echo "✅ All services stopped!"
echo "=================================================="
echo ""
echo "To completely remove data volumes:"
echo "  docker-compose down -v"
echo ""
