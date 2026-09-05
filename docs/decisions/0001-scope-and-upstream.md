# 0001: Build a bitemporal fact kernel, not an agent stack

- Status: Accepted
- Date: 2026-09-05

## Context

Agent memory projects often combine extraction, retrieval, vector storage, orchestration, and application services. That breadth makes it hard to preserve a precise answer to two independent questions: when a fact was valid and when the system knew it.

Mooncakes already contains memory, agent, retrieval, and vector-oriented packages. Graphiti supplies a valuable model of evolving graph knowledge, but a full port would inherit databases, services, providers, and Python API constraints unrelated to a compact MoonBit library.

## Decision

FactEpoch-mbt will implement a pure-MoonBit bitemporal fact-graph kernel under Apache-2.0. The portable root owns domain types, deterministic event application, replay, temporal queries, explicit supersession/retraction, provenance, local search helpers, and frozen forget planning.

The upstream semantic reference is Graphiti `0.30.1` at commit `547422865cca9fb5a82915c074d899428c145ff4`. Only deterministic model, time, pre-ID entity-reference candidate deduplication, and ranking behavior will be considered for fixture-level migration. The project does not promise full or drop-in compatibility.

FactEpoch will use canonical JSONL and SHA-256 integrity receipts as its own storage interchange. File publication, clock access, and the optional non-streaming OpenAI-compatible adapter remain native boundaries. The default extractor and all normal tests are offline.

Supersession requires explicit old fact IDs plus same-group and structural checks. This deliberate adaptation prevents cross-slot invalidation of the kind documented in Graphiti issue #1728.

## Consequences

- Applications gain historical reconstruction and source explanations without adopting a database service.
- The project must maintain strict canonicalization, replay, ordering, and cross-target fixtures.
- Callers remain responsible for truth policy, identifiers, timestamps, storage access control, and secure erasure.
- Search backends can provide ranked candidates, but embeddings and BM25 databases remain outside the kernel.
- Redact compaction creates a new artifact and cannot erase the source or its copies.

## Alternatives rejected

- **Full Graphiti port:** too broad and incompatible with a focused MoonBit library boundary.
- **Latest-value storage:** loses known-time history and late-arrival semantics.
- **Last-write-wins or confidence-based invalidation:** hides a decision that must be auditable.
- **Database as v1 source of truth:** weakens portable replay and fixture inspection.
- **In-place compaction:** risks the only historical artifact.
- **Live model extraction by default:** introduces nondeterminism, credentials, cost, and disclosure into the normal path.

## Review triggers

A new decision record is required before changing the event schema, canonical bytes, hash domains, time units, interval meaning, conflict guard, forget semantics, compaction guarantees, core target support, license, or pinned Graphiti baseline.
