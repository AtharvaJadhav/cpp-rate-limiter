#include <httplib.h>
#include <sw/redis++/redis++.h>
#include <nlohmann/json.hpp>
#include <chrono>
#include <string>
#include <iostream>
#include <thread>
#include <atomic>

using json = nlohmann::json;
using namespace sw::redis;
using namespace std::chrono;

class RateLimiter {
private:
    Redis redis;
    std::atomic<uint64_t> total_requests{0};
    std::atomic<uint64_t> allowed_requests{0};
    std::atomic<uint64_t> denied_requests{0};
    
    // Lua script for atomic token bucket operations
    const std::string lua_script = R"(
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local requested_tokens = tonumber(ARGV[3])
        local now = tonumber(ARGV[4])
        
        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now
        
        -- Calculate tokens to add based on time elapsed
        local time_elapsed = now - last_refill
        local tokens_to_add = time_elapsed * refill_rate / 1000000  -- microseconds to seconds
        tokens = math.min(capacity, tokens + tokens_to_add)
        
        local allowed = 0
        if tokens >= requested_tokens then
            tokens = tokens - requested_tokens
            allowed = 1
        end
        
        -- Update bucket state
        redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
        redis.call('EXPIRE', key, 3600)  -- 1 hour TTL
        
        return {allowed, tokens}
    )";

public:
    RateLimiter(const std::string& redis_url) : redis(redis_url) {
        try {
            redis.ping();
            std::cout << "✓ Connected to Redis" << std::endl;
        } catch (const Error& e) {
            std::cerr << "Redis connection failed: " << e.what() << std::endl;
            throw;
        }
    }

    struct RateLimitResult {
        bool allowed;
        double remaining_tokens;
        uint64_t retry_after_ms;
    };

    RateLimitResult check_rate_limit(const std::string& client_id, 
                                   int capacity = 100, 
                                   double refill_rate = 10.0,  // tokens per second
                                   int requested_tokens = 1) {
        
        total_requests++;
        
        auto now = duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
        
        try {
            auto result = redis.eval<std::vector<long long>>(
                lua_script,
                {"rate_limit:" + client_id},
                {std::to_string(capacity), 
                 std::to_string(refill_rate), 
                 std::to_string(requested_tokens), 
                 std::to_string(now)}
            );
            
            bool allowed = result[0] == 1;
            double remaining = static_cast<double>(result[1]);
            
            if (allowed) {
                allowed_requests++;
            } else {
                denied_requests++;
            }
            
            // Calculate retry after (when next token will be available)
            uint64_t retry_after = remaining < capacity ? 
                static_cast<uint64_t>((1.0 / refill_rate) * 1000) : 0;
            
            return {allowed, remaining, retry_after};
            
        } catch (const Error& e) {
            std::cerr << "Redis error: " << e.what() << std::endl;
            // Fail open - allow request if Redis is down
            return {true, static_cast<double>(capacity), 0};
        }
    }
    
    json get_metrics() {
        auto total = total_requests.load();
        return json{
            {"total_requests", total},
            {"allowed_requests", allowed_requests.load()},
            {"denied_requests", denied_requests.load()},
            {"allow_rate", total > 0 ? static_cast<double>(allowed_requests) / total : 1.0}
        };
    }
};

int main() {
    // Configuration
    const std::string redis_url = std::getenv("REDIS_URL") ? 
        std::getenv("REDIS_URL") : "tcp://127.0.0.1:6379";
    const int port = std::getenv("PORT") ? 
        std::stoi(std::getenv("PORT")) : 8080;
    
    std::cout << "Starting Rate Limiter Service..." << std::endl;
    std::cout << "Redis URL: " << redis_url << std::endl;
    std::cout << "Port: " << port << std::endl;
    
    try {
        RateLimiter limiter(redis_url);
        httplib::Server server;
        
        // CORS headers for testing
        server.set_default_headers({
            {"Access-Control-Allow-Origin", "*"},
            {"Access-Control-Allow-Methods", "GET, POST, OPTIONS"},
            {"Access-Control-Allow-Headers", "Content-Type"}
        });
        
        // Rate limiting endpoint
        server.Post("/check", [&](const httplib::Request& req, httplib::Response& res) {
            auto start = high_resolution_clock::now();
            
            try {
                json request_body = json::parse(req.body);
                
                std::string client_id = request_body.value("client_id", "default");
                int capacity = request_body.value("capacity", 100);
                double refill_rate = request_body.value("refill_rate", 10.0);
                int tokens = request_body.value("tokens", 1);
                
                auto result = limiter.check_rate_limit(client_id, capacity, refill_rate, tokens);
                
                auto end = high_resolution_clock::now();
                auto duration_us = duration_cast<microseconds>(end - start).count();
                
                json response = {
                    {"allowed", result.allowed},
                    {"remaining_tokens", result.remaining_tokens},
                    {"retry_after_ms", result.retry_after_ms},
                    {"latency_us", duration_us}
                };
                
                res.status = result.allowed ? 200 : 429;
                res.set_content(response.dump(), "application/json");
                
            } catch (const std::exception& e) {
                json error = {{"error", e.what()}};
                res.status = 400;
                res.set_content(error.dump(), "application/json");
            }
        });
        
        // Health check endpoint
        server.Get("/health", [](const httplib::Request&, httplib::Response& res) {
            json health = {{"status", "healthy"}};
            res.set_content(health.dump(), "application/json");
        });
        
        // Metrics endpoint
        server.Get("/metrics", [&](const httplib::Request&, httplib::Response& res) {
            auto metrics = limiter.get_metrics();
            res.set_content(metrics.dump(), "application/json");
        });
        
        // Simple GET endpoint for load testing
        server.Get("/check", [&](const httplib::Request& req, httplib::Response& res) {
            auto start = high_resolution_clock::now();
            
            std::string client_id = "load_test";
            auto result = limiter.check_rate_limit(client_id, 1000, 100.0, 1);
            
            auto end = high_resolution_clock::now();
            auto duration_us = duration_cast<microseconds>(end - start).count();
            
            json response = {
                {"allowed", result.allowed},
                {"remaining", result.remaining_tokens},
                {"latency_us", duration_us}
            };
            
            res.status = result.allowed ? 200 : 429;
            res.set_content(response.dump(), "application/json");
        });
        
        std::cout << "✓ Server starting on port " << port << std::endl;
        std::cout << "Endpoints:" << std::endl;
        std::cout << "  POST /check - Rate limit check" << std::endl;
        std::cout << "  GET /check - Simple rate limit (for load testing)" << std::endl;
        std::cout << "  GET /health - Health check" << std::endl;
        std::cout << "  GET /metrics - Service metrics" << std::endl;
        
        server.listen("0.0.0.0", port);
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
}