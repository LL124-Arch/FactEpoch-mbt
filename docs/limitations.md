# Limitations

This page records claims FactEpoch does not make.

## Current status

The repository contains a buildable, tested portable core for domain values, event replay, explicit terminal closures, bitemporal reads, explanations, and pre-ID candidate deduplication. Pinned Graphiti fixtures and Python drift tools are present. There is no CLI, published Mooncakes artifact, performance result, ranked retrieval, journal, or compaction implementation yet.

## Version-one limits

- The core is an in-memory deterministic projection, not a graph database or distributed service.
- No SQLite, Neo4j, FalkorDB, Kuzu, Neptune, ANN index, or BM25 database is included.
- BFS is bounded and intended for local neighborhoods, not unbounded graph analytics.
- Cosine and RRF operate on caller-provided data; FactEpoch does not create embeddings.
- Graphiti support is selective and fixture-scoped, not API-compatible or drop-in.
- Unicode compatibility is limited to CPython `3.12.14` with UCD `15.0.0`; no claim is made for every Graphiti/Python/Unicode combination, and NFC/NFD remain distinct.
- Valid time is supplied by the caller or an untrusted extractor candidate; the kernel validates structure, not truth.
- A confidence score is evidence metadata, not an automatic conflict decision.
- Dynamic ontologies, communities, MCP, REST, Web UI, streaming extraction, tool calling, provider discovery, and multi-provider SDK behavior are excluded.

## Integrity limits

SHA-256 detects content mismatch only relative to a separately trusted digest. It does not authenticate writers, encrypt facts, prevent rollback when both file and digest are replaced, or prove that a statement is true.

Canonical JSONL is append-oriented but does not itself coordinate concurrent writers. The native CLI assumes a single writer. Crash visibility guarantees depend on the host filesystem and do not include a universal directory-fsync guarantee.

## Forgetting and redaction limits

Applying a forget plan is logical state change. Source bytes remain in the original event stream. Redact compaction omits confirmed bodies from a new artifact but cannot remove copies in the old journal, backups, logs, caches, temporary files, filesystem snapshots, or physical media. Operators remain responsible for retention and secure erasure.

Preserve compaction must retain all observable history; it is not a privacy operation. Redact history may return markers and digests where source text is no longer available.

## Extraction limits

The optional OpenAI-compatible adapter sends caller-approved content to an explicit endpoint. It cannot guarantee model correctness or provider retention behavior. It has no retry or streaming layer, returns candidates only, and requires application review before event creation.
