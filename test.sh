#!/bin/bash

echo "🧪 Rate Limiter Test Suite"
echo "=========================="

SERVICE_URL=${1:-"http://localhost:8080"}

# Check if service is running
if ! curl -s "$SERVICE_URL/health" > /dev/null; then
    echo "❌ Service not reachable at $SERVICE_URL"
    exit 1
fi

echo "✅ Service is running"

# Test 1: Health check
echo ""
echo "🔍 Test 1: Health Check"
response=$(curl -s "$SERVICE_URL/health")
echo "Response: $response"

if echo "$response" | grep -q "healthy"; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    exit 1
fi

# Test 2: Basic rate limit check
echo ""
echo "🔍 Test 2: Basic Rate Limit Check"
response=$(curl -s -X POST "$SERVICE_URL/check" \
    -H "Content-Type: application/json" \
    -d '{"client_id":"test_client","capacity":5,"refill_rate":1,"tokens":1}')

echo "Response: $response"

if echo "$response" | grep -q '"allowed":true'; then
    echo "✅ Rate limit check passed"
else
    echo "❌ Rate limit check failed"
    exit 1
fi

# Test 3: Rate limit exhaustion
echo ""
echo "🔍 Test 3: Rate Limit Exhaustion"
echo "Sending 10 requests quickly to exhaust tokens..."

allowed=0
denied=0

for i in {1..10}; do
    response=$(curl -s -X POST "$SERVICE_URL/check" \
        -H "Content-Type: application/json" \
        -d '{"client_id":"exhaustion_test","capacity":3,"refill_rate":0.1,"tokens":1}')
    
    if echo "$response" | grep -q '"allowed":true'; then
        allowed=$((allowed + 1))
    else
        denied=$((denied + 1))
    fi
done

echo "Allowed: $allowed, Denied: $denied"

if [ $denied -gt 0 ]; then
    echo "✅ Rate limiting works correctly"
else
    echo "❌ Rate limiting not working"
    exit 1
fi

# Test 4: GET endpoint for load testing
echo ""
echo "🔍 Test 4: GET Endpoint"
response=$(curl -s "$SERVICE_URL/check")
echo "Response: $response"

if echo "$response" | grep -q '"allowed"'; then
    echo "✅ GET endpoint works"
else
    echo "❌ GET endpoint failed"
    exit 1
fi

# Test 5: Metrics endpoint
echo ""
echo "🔍 Test 5: Metrics Endpoint"
response=$(curl -s "$SERVICE_URL/metrics")
echo "Response: $response"

if echo "$response" | grep -q '"total_requests"'; then
    echo "✅ Metrics endpoint works"
else
    echo "❌ Metrics endpoint failed"
    exit 1
fi

# Test 6: Performance test (small scale)
echo ""
echo "🔍 Test 6: Basic Performance Test"
echo "Sending 100 requests..."

start_time=$(date +%s%N)
for i in {1..100}; do
    curl -s "$SERVICE_URL/check" > /dev/null
done
end_time=$(date +%s%N)

duration_ms=$(( (end_time - start_time) / 1000000 ))
rps=$(( 100000 / duration_ms ))

echo "100 requests in ${duration_ms}ms"
echo "Rate: ~${rps} requests/second"

if [ $rps -gt 1000 ]; then
    echo "✅ Performance test passed (>1000 RPS)"
else
    echo "⚠️  Performance lower than expected"
fi

echo ""
echo "🎉 All tests completed!"
echo ""
echo "Final metrics:"
curl -s "$SERVICE_URL/metrics" | jq '.' 2>/dev/null || curl -s "$SERVICE_URL/metrics"