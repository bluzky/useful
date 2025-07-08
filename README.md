# Useful

A collection of 13 helper modules for common Elixir development patterns. Each module is self-contained and can be copied independently to your project.

## Overview

This library provides utilities for data manipulation, caching, routing, command patterns, and more. All modules follow standard Elixir conventions and are designed to be standalone utilities.

## Modules

### 1. ECache
Distributed cache with pluggable adapters (ETS/Mnesia) and Redis PubSub for cross-node invalidation. Supports cache loading with fallback, conditional invalidation, and manual cache operations.

### 2. Pipeline
Sequential step execution utility inspired by Ecto.Multi for composing named operations with automatic error handling and rollback capabilities.

### 3. Commands
Command chaining pattern with automatic error handling and rollback capabilities. Allows access to previous results and execution rollback on errors.

### 4. DataMatcher
Flexible pattern matching for primitives, collections, and nested structures with string patterns and quantifiers.

### 5. DataRouter
Routes data to queues based on pattern matching using DataMatcher. Supports multiple routes defined in a map.

### 6. DefEnum
Macro for defining typed enums with Ecto integration. Supports typed structs and automatic generation of functions for working with enum values.

### 7. DefConfig
Macro for defining configurations with types and defaults. Supports input casting and default configuration values.

### 8. Delegator
Macro for controlled function delegation between modules, allowing for flexible and controlled function delegation.

### 9. RedisLock
Redis-based distributed locking using Redix for coordinating access to shared resources across multiple processes or nodes.

### 10. Crypto
AES-256-GCM encryption/decryption utilities with key generation for secure data handling.

### 11. Filter
Dynamic query building from conditions. Helper to build queries dynamically from map or list of conditions.

### 12. Nested
Utilities for working with nested collections, providing helpers for deep data structure manipulation.

### 13. PingEndpoint
Simple health check endpoint providing a 'ping' route that returns a 'pong' response for service deployment status.

### 14. JsonCompactor
Data structure optimization tool that compacts JSON-like structures by flattening nested maps, lists, and strings into arrays with reference indices for memory efficiency and deduplication.

## Usage

Each module can be copied independently to your project. Simply copy the desired module from the `lib/` directory and its corresponding test file from the `test/` directory.

## Dependencies

Main dependencies include:
- `ecto` for database abstractions
- `jason` for JSON handling
- `plug_cowboy` for HTTP functionality
- `redix` for Redis operations
- `phoenix_pubsub` and `phoenix_pubsub_redis` for distributed messaging

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/ecache_test.exs

# Run test with coverage (basic)
mix test --cover

# Run test with detailed coverage report
mix coveralls

# Generate HTML coverage report
mix coveralls.html

# Show detailed coverage per file
mix coveralls.detail
```

## Development

```bash
# Format code
mix format

# Compile project
mix compile

# Get dependencies
mix deps.get
```
