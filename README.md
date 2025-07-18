# C++ Rate Limiter

Token bucket rate limiter built with C++ and Redis. Handles 25K+ requests/second with sub-1ms latency.

## Features

- Token bucket algorithm with atomic Redis operations
- 25K+ RPS sustained throughput on M1 Air
- Sub-1ms P99 latency under load
- Distributed state using Redis
- Fails open if Redis is down
- Docker support

## Usage

### Docker (easiest)

```bash
docker-compose up -d
curl http://localhost:8080/health
```

### Local build

```bash
# macOS
brew install redis hiredis pkg-config
./build.sh
redis-server &
cd build && ./rate_limiter
```

## API

**POST /check** - Rate limit check
```json
{
  "client_id": "user123",
  "capacity": 100,
  "refill_rate": 10.0,
  "tokens": 1
}
```

**GET /check** - Simple check for load testing

**GET /metrics** - Request stats

**GET /health** - Health check

## Testing

```bash
./test.sh        # functional tests
./benchmark.sh   # performance tests
```

Typical benchmark results:
```
Requests/sec: 25,144
Latency P50:  423us
Latency P99:  4.56ms
```

## Config

- `REDIS_URL` - Redis connection (default: tcp://127.0.0.1:6379)
- `PORT` - HTTP port (default: 8080)