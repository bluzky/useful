# Collection of useful helper modules that just copy and add to your project

### 1. RedisLock
A simple implement of redis lock using Redix
### 2. DefEnum
A module providing a macro to define enums, supporting typed structs and automatic generation of functions for working with enum values, along with Ecto integration.
### 3. QueryFilter
Helper to build query dynamically from map or list of conditions
### 4. Nested
Helper to work with nested collection
### 5. DataMatcher
A module for flexible data matching, supporting pattern matching for primitives, collections, and nested structures with string patterns and quantifiers.
### 6. Crypto
A module providing basic encryption and decryption functions using AES-256-GCM, including key generation.
### 7. Commands
A module providing a command chaining pattern for sequential operations with automatic error handling, allowing access to previous results and execution rollback on errors.
### 8. DataRouter
A module for routing data to specific queues based on pattern matching, using DataMatcher for logic and supporting multiple routes defined in a map.
### 9. DefConfig
A module providing a macro to define configurations with types and default values, supporting features like input casting and default configuration values.
### 10. Delegator
A module providing a macro to delegate functions from another module, allowing for flexible and controlled function delegation.
### 11. Ecache
A distributed cache implementation with pluggable storage adapters and Redis-based PubSub for cross-node invalidation, supporting cache loading with fallback, conditional invalidation, and manual cache operations.
### 12. PingEndpoint
A simple endpoint for checking service deployment status, providing a 'ping' route that returns a 'pong' response.
