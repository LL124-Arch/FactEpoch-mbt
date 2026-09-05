# Architecture

This document describes the intended package boundaries. It does not claim that the packages already exist.

## Layers

An arrow means “imports.”

```text
cmd / examples ---------> root
       |                   |
       +-> codec/jsonl ----+----> integrity ----> moonbitlang/x + UTF-8/bytes
       |       |           |
       +-> compact --------+
       |
       +-> extract/api <--- extract/fixture
                  ^
                  |
          extract/openai_compat (native only)
```

The root package is the owner of every public ID, fact, event, query, result, conflict, provenance, and forget type. It owns canonical semantic-state serialization and calls byte-oriented integrity primitives for state digests and `ApplyReport`. `integrity` depends only on `moonbitlang/x`, UTF-8, and byte primitives and knows no root type. `codec/jsonl` and `compact` may depend on both root and integrity. This keeps dependencies acyclic and makes the generated root interface the compatibility boundary.

## Portable core

Root `moon.pkg` and root `*.mbt` files contain:

- opaque IDs and `Timestamp`;
- `Episode`, `Entity`, `FactObject`, `FactAssertion`, and `Provenance`;
- pre-ID `CandidateFact` values, pinned Graphiti normalization, deterministic candidate deduplication, and materialization;
- `MemoryEvent`, validation, atomic application, and replay;
- bitemporal query, history, diff, neighbors, and explain;
- explicit conflict/supersession and retraction;
- frozen forget planning and logical application;
- stable filtering, BFS, cosine, and RRF.

These files support `wasm`, `wasm-gc`, `js`, and `native`. They receive all nondeterministic inputs explicitly and contain no filesystem or HTTP behavior.

The implemented slice includes atomic ingestion/replay, explicit closure-aware reads, explanation, pre-ID candidate deduplication, ranked-candidate fusion, cosine, and bounded BFS. Forgetting, journals, and integrity remain architectural commitments below, not hidden capabilities of the present root package.

## Event flow

```text
candidate/input
      |
      v
validate per-stream sequence/time order, IDs, references, intervals, provenance and structure
      |
      v
stage the complete batch on an isolated state copy
      |
      +-- any error --> discard staged state; return MemoryError
      |
      v
publish state + ApplyReport (counts and event IDs in the current slice)
      |
      v
canonical envelope -> SHA-256 chain -> append-only JSONL
```

The in-memory graph and persisted event stream share the same semantic validators. Per stream, `seq` must strictly increase and `recorded_at_ms` must be monotonic nondecreasing; `seq` orders events recorded in the same millisecond. A journal decoder does not gain authority to bypass batch atomicity. `replay` begins from an empty graph and applies the validated sequence in order.

## Bitemporal projection

Facts retain valid intervals in their assertions. Known-time visibility is derived from envelope order:

- assertion or supersession activation opens visibility at `recorded_at`;
- an explicit supersession, retraction, or applied forget plan closes visibility at its event time;
- late assertions may backfill an earlier `valid_from`, but never backdate known time before their actual `recorded_at_ms`;
- a query takes the stream prefix with `recorded_at <= known_at`, including every sequence at the boundary millisecond, rebuilds it through the normal `MemoryGraph::replay` path, then filters half-open valid intervals at `valid_at`.

The replay rule is authoritative; reads never filter a graph that already contains future events. Because `recorded_at` is monotonic, prefix collection stops at the first future envelope. Normal replay rebuilds private ID indexes with expected linear work. Closure events derive an effective `valid_to` without mutating the stored assertion: supersession uses the earlier of the old bound and the new fact's `valid_from`, while retraction carries an explicit `effective_at`. Applied forget plans will later hide material from normal query results while retaining audit markers.

Indexes are derived accelerators. They may be rebuilt from events and never define independent truth.

Retrieval never creates a second visibility path. Ranked IDs are intersected with an unbounded internal valid/known-time projection before the requested output limit. BFS uses that projection, processes complete breadth-first layers, treats Literal facts as non-expanding outgoing leaves, and orders each layer by confidence, valid start, and FactId. External rankings and Map iteration cannot bypass these rules.

## Determinism

All observable arrays have a documented stable order. Sets are sorted before hashing or encoding. Map iteration does not enter result order, canonical JSON, state digests, or receipts. The core accepts caller-supplied IDs and timestamps instead of consulting ambient state.

Predicate structure uses an ASCII-only key: lowercase `A` through `Z`, collapse and trim whitespace bytes `0x09` through `0x0D` and `0x20`, and preserve all other Unicode, underscore, and hyphen characters. Source predicates remain unchanged.

Graphiti candidate statements deliberately use a different compatibility profile: CPython `3.12.14`/UCD `15.0.0` `str.lower()` followed by Python Unicode `\s+` collapse/strip. Generated lowercase, contextual-casing, and all 29 whitespace scalars keep that behavior portable across MoonBit's four targets. The generator validates fixed table counts and fully expands every compressed table back to the runtime-derived source set. Contextual final sigma is computed with linear forward/backward state; Map values are only looked up, never iterated for result order. Neither profile performs NFC/NFD normalization.

`graphiti_fixture_vectors.generated_wbtest.mbt` is regenerated from the candidate JSON fixtures by its strict fixed-profile Python oracle. The search oracle likewise validates executable exact/adaptation inputs and expectations, renders all of `graphiti_search_fixture.generated_wbtest.mbt`, and byte-compares it under `--check`. `.gitattributes` marks generated MoonBit artifacts for repository tooling. Release LOC reporting lists generated production tables and generated tests separately from handwritten source and tests.

The in-memory graph keeps private ID-to-array-position maps for event, episode, entity, and fact lookup. An apply operation copies these indexes alongside its arrays and publishes both only after complete validation. Arrays remain the source of observable order; indexes are never iterated to produce snapshots, serialization, or query results.

The compatibility corpus runs on all four core targets. Native-only packages have separate checks so a platform adapter cannot narrow the portable module accidentally.

## Storage and integrity

`codec/jsonl` owns the version-one event schema and canonical event bytes. The root owns canonical semantic-state bytes, and `compact` owns artifact and redaction-set bytes. Each passes bytes and a domain tag to `integrity`, which wraps `moonbitlang/x@0.5.1` SHA-256 without importing root types.

The JSONL file is authoritative for replay. Hash verification detects inconsistency relative to a trusted expected digest. It does not authenticate authors and does not protect confidentiality.

## Forget and compact

Forgetting has two distinct phases:

1. `plan_forget` resolves a selector to an exact, sorted ID set bound to a semantic-state digest.
2. Applying that frozen plan appends one logical event. It never reruns a cascade against later state.

Compaction is a native file operation outside the portable core. Preserve compaction retains every observable historical answer. Redact compaction omits confirmed forgotten bodies only from a newly published generation while retaining digests and audit markers. Both modes keep the input unchanged.

## Extraction

The extraction boundary is intentionally one-way:

```text
source content -> Extractor -> untrusted ExtractionBatch -> caller validation -> MemoryEvent
```

An extractor cannot allocate authoritative IDs, choose system time, identify a fact to retract or supersede, compute chain hashes, or mutate `MemoryGraph`. The fixture extractor is the default and fully offline.

The OpenAI-compatible adapter is isolated in a native package using `moonbitlang/async@0.21.2`. Its injected transport makes protocol tests deterministic. The normal core and examples do not depend on credentials or live networking.

## CLI responsibility

`cmd/factepoch` supplies operational concerns the core refuses to own: reading current UTC time, allocating stream-local sequence numbers and default IDs, reading/writing files, selecting a compaction output, and rendering diagnostics.

`cmd/factepoch-openai-demo` is a separate opt-in executable. Normal CLI commands do not silently invoke it.

## Dependency policy

The initial intended external modules are:

- `moonbitlang/x@0.5.1` for pure-MoonBit SHA-256;
- `moonbitlang/async@0.21.2` only for native extraction and I/O boundaries.

Every dependency must be recorded in `moon.mod`, reviewed for target impact and license, and reflected in `THIRD_PARTY.md` when required.
