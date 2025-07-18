#!/bin/bash

echo "🚀 Rate Limiter Benchmark Suite"
echo "================================"

SERVICE_URL=${1:-"http://localhost:8080"}

# Check if service is running
if ! curl -s "$SERVICE_URL/health" > /dev/null; then
    echo "❌ Service not reachable at $SERVICE_URL"
    echo "Make sure the rate limiter is running:"
    echo "  docker-compose up -d"
    echo "  # or"
    echo "  cd build && ./rate_limiter"
    exit 1
fi

echo "✅ Service is running at $SERVICE_URL"

# Check for required tools
command -v wrk >/dev/null 2>&1 || { 
    echo "❌ wrk not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install wrk
    else
        echo "Please install wrk: https://github.com/wg/wrk"
        exit 1
    fi
}

echo ""
echo "🔥 Running Benchmark Tests..."
echo ""

# Test 1: Baseline performance
echo "📊 Test 1: Baseline Performance (30s)"
echo "Threads: 4, Connections: 100"
wrk -t4 -c100 -d30s --latency "$SERVICE_URL/check"
echo ""

# Test 2: High concurrency
echo "📊 Test 2: High Concurrency (15s)"
echo "Threads: 8, Connections: 200"
wrk -t8 -c200 -d15s --latency "$SERVICE_URL/check"
echo ""

# Test 3: Burst test
echo "📊 Test 3: Burst Test (10s)"
echo "Threads: 12, Connections: 300"
wrk -t12 -c300 -d10s --latency "$SERVICE_URL/check"
echo ""

# Test 4: Single connection latency
echo "📊 Test 4: Single Connection Latency (10s)"
echo "Threads: 1, Connections: 1"
wrk -t1 -c1 -d10s --latency "$SERVICE_URL/check"
echo ""

# Get final metrics
echo "📈 Service Metrics:"
curl -s "$SERVICE_URL/metrics" | jq '.' || curl -s "$SERVICE_URL/metrics"
echo ""

echo "✅ Benchmark Complete!"
echo ""
echo "💡 Tips for better performance:"
echo "  • Increase Redis memory if needed"
echo "  • Monitor CPU usage during tests"
echo "  • Check Docker resource limits"
echo "  • For production: use connection pooling"