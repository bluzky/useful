# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir library called "Useful" that provides a collection of helper modules for common development patterns. The library contains 13 main utility modules that can be copied and added to other projects.

## Architecture

The project follows standard Elixir library conventions:
- `lib/` contains all modules
- `test/` contains corresponding test files
- Each module is self-contained and can be used independently
- Core utilities focus on data manipulation, caching, routing, and command patterns

### Key Modules

- **ECache**: Distributed cache with pluggable adapters (ETS/Mnesia) and Redis PubSub for cross-node invalidation
- **Pipeline**: Sequential step execution utility inspired by Ecto.Multi for composing named operations
- **Commands**: Command chaining pattern with automatic error handling and rollback capabilities
- **DataMatcher**: Flexible pattern matching for primitives, collections, and nested structures
- **DataRouter**: Routes data to queues based on pattern matching using DataMatcher
- **DefEnum**: Macro for defining typed enums with Ecto integration
- **DefConfig**: Macro for defining configurations with types and defaults
- **Delegator**: Macro for controlled function delegation between modules
- **RedisLock**: Redis-based distributed locking using Redix
- **Crypto**: AES-256-GCM encryption/decryption utilities
- **Filter**: Dynamic query building from conditions
- **Nested**: Utilities for working with nested collections
- **PingEndpoint**: Simple health check endpoint
- **JsonCompactor**: Data structure optimization tool that compacts JSON-like structures by flattening nested maps, lists, and strings into arrays with reference indices for memory efficiency and deduplication

## Development Commands

### Testing
```bash
# Run all tests
mix test

# Run specific test file
mix test test/ecache_test.exs

# Run test with coverage
mix test --cover

# Run tests with detailed output
mix test --trace
```

### Code Quality
```bash
# Format code
mix format

# Check if code is formatted
mix format --check-formatted

# Compile project
mix compile

# Get dependencies
mix deps.get
```

### Benchmarking
```bash
# Run benchmarks (located in bench/ directory)
mix run bench/json_compactor_bench.exs

# Run quick benchmarks
mix run bench/json_compactor_quick_bench.exs
```

### Dependencies
The project uses these main dependencies:
- `ecto` for database abstractions
- `jason` for JSON handling
- `plug_cowboy` for HTTP functionality
- `redix` for Redis operations
- `phoenix_pubsub` and `phoenix_pubsub_redis` for distributed messaging

## Module Interactions

- **ECache** uses Phoenix.PubSub for cross-node cache invalidation
- **DataRouter** leverages **DataMatcher** for routing logic
- **Commands** provides error handling patterns that complement **Pipeline**
- Most modules are designed to be standalone utilities that can be copied independently