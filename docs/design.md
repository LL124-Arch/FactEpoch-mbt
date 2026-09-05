# FactEpoch-mbt v1 Design Contract

This document freezes the intended public behavior for v1. Foundation types and atomic application of `RecordEpisode`, `PutEntity`, and `AssertFact` are implemented. Supersession, retraction, query, journal, compaction, CLI, and extraction sections remain a contract to test against rather than a claim of current availability.

## Purpose

FactEpoch is a deterministic, embeddable memory kernel for facts whose history matters. It separates:

- **valid time**: when an assertion is true in the modeled world;
- **known time**: when an event made that assertion available to the system.

A late event may describe an old valid interval without pretending the system knew it earlier. The frozen query design reconstructs historical answers by replaying only events recorded at or before `known_at`, then selecting facts whose half-open valid interval contains `valid_at`; that query engine is not implemented in the foundation stage.

## Portability and ownership

The root package owns every public domain type and `MemoryGraph`. It must build for `wasm`, `wasm-gc`, `js`, and `native`. The root package never reads a clock, environment variable, file, database, random source, or network endpoint. Identifiers and `recorded_at` are supplied by callers.

There is one module, `LL124-Arch/factepoch`, and one `moon.mod`. The root depends only on the low-level `integrity` package; `integrity` knows no root types and depends only on `moonbitlang/x`, UTF-8, and byte primitives. Other supporting packages may depend on the root contract. Native file and HTTP behavior stays outside the portable root.

## Time model

`Timestamp` is a signed UTC Unix millisecond value.

```text
Timestamp::from_unix_millis(Int64) -> Timestamp
Timestamp::to_unix_millis(Self) -> Int64
```

There is no implicit timezone parsing or system-clock constructor in the core. A fact interval is `[valid_from, valid_to)`: the start is included and the optional end is excluded. `None` for `valid_to` means no known end. Construction rejects an end less than or equal to its start.

Within each stream, `seq` strictly increases and `recorded_at_ms` is monotonic nondecreasing. Events recorded in the same millisecond are ordered by `seq`. `known_at` is inclusive at event granularity: replay includes envelopes with `recorded_at_ms <= known_at`. A late arrival may backfill an earlier valid interval, but its known time remains its actual later `recorded_at_ms`; no event can backdate system knowledge.

## Opaque identifiers

These public IDs are distinct opaque types:

```text
EventId
EpisodeId
EntityId
FactId
GroupId
Digest256
```

Their public `new` constructors validate a non-empty UTF-8 string of at most 255 encoded bytes. Their `value` methods return immutable strings. Equality and comparison are type-specific and byte-stable. `Digest256` accepts exactly 64 lowercase hexadecimal characters and exposes no mutable bytes. The core does not generate IDs.

### Canonical metadata

The implementation uses an opaque `Metadata` value instead of exposing `Map` ownership or iteration order. `Metadata::new(Array[(String, String)])` copies its input, rejects empty or duplicate keys, and sorts by key. `entries` returns a defensive copy in canonical order. This is the concrete MoonBit representation of the `sorted Map[String, String]` notation used in the original design baseline.

## Public domain types

The root package exposes these records and enums. The generated interface captures the exact implemented constructor and accessor syntax; the names and semantic fields below are fixed for v1.

### Episode

```text
Episode
  id: EpisodeId
  group_id: GroupId
  body: String
  source_uri: String?
  occurred_from: Timestamp?
  occurred_to: Timestamp?
  metadata: Metadata
```

An episode is source material. Its optional occurrence interval does not substitute for a fact's valid interval.

### Entity

```text
Entity
  id: EntityId
  group_id: GroupId
  name: String
  kind: String
  summary: String?
  metadata: Metadata
```

### FactObject and FactAssertion

```text
FactObject
  EntityRef(EntityId)
  Literal(String)

FactAssertion
  id: FactId
  group_id: GroupId
  subject: EntityId
  predicate: String
  object: FactObject
  statement: String
  valid_from: Timestamp
  valid_to: Timestamp?
  confidence_basis_points: Int
  provenance: Provenance
```

Confidence is an integer from 0 to 10,000. It affects optional scoring but never grants permission to supersede another fact.

### Provenance

```text
Provenance
  episode_ids: non-empty sorted Array[EpisodeId]
  evidence: sorted Array[EvidenceSpan]
  extractor: String?

EvidenceSpan
  episode_id: EpisodeId
  start_utf8: Int
  end_utf8: Int
  excerpt_digest: Digest256?
```

Evidence offsets refer to UTF-8 byte offsets in the corresponding episode body. `EvidenceSpan::validate_for_body` rejects out-of-bounds offsets and offsets inside a multi-byte code point. A `Provenance` value copies, sorts, and deduplicates only its own episode IDs and evidence spans; it never absorbs provenance from another authoritative fact. Every evidence span must name an episode in the same provenance value. Event application will additionally require every referenced episode to be visible in the fact's group.

## Events

`MemoryEvent` has these variants:

```text
RecordEpisode(Episode)
PutEntity(Entity)
AssertFact(FactAssertion)
SupersedeFact(new_fact: FactAssertion, old_fact_ids: Array[FactId], decision: ConflictDecision)
RetractFact(fact_id: FactId, reason: String)
ApplyForgetPlan(ForgetPlan)
```

The current root interface exposes the first three variants. The remaining
variants stay frozen here for later milestones and are not runtime claims.

`RecordedEvent` supplies `stream_id`, `seq`, `event_id`, `recorded_at`, and the semantic event. The JSONL envelope adds chain hashes without changing those ordering fields.

`PutEntity` is an idempotent upsert only when an existing entity has identical canonical content. Changing content under the same entity ID is a conflict. Entity evolution will use explicit new events rather than hidden mutation.

An accepted fact is stored privately with its immutable assertion, first activation event ID, first activation `recorded_at`, and an empty closure slot reserved for explicit supersession or retraction. A later event carrying the same canonical `FactAssertion` is a semantic no-op and cannot replace that first activation metadata.

### Idempotence and atomic batches

`MemoryGraph::apply` prevalidates an entire batch against a staged copy of state. If any event is invalid, the method returns `MemoryError` and publishes none of the batch. Within a successful batch, later events may reference earlier events in that batch.

Reapplying an event ID with the same complete `RecordedEvent` is an idempotent no-op reported in `ApplyReport`; this identity check runs before stream and ordering checks, so an old exact event can be retried safely. Reusing an event ID with any changed stream, sequence, recorded time, variant, or domain payload returns `EventIdConflict`. A batch containing an internally conflicting duplicate also fails atomically.

Reference group errors carry a typed `GroupReference`: `SubjectReference(EntityId)`, `ObjectReference(EntityId)`, or `ProvenanceReference(EpisodeId)`. Error handling therefore does not depend on role-name strings and never includes an episode body, fact statement/literal, or metadata value.

## Candidate deduplication and authoritative identity

Graphiti-compatible deduplication happens before official IDs are allocated. An `exact_upstream` helper processes entity-reference candidates within one group-scoped candidate set. Its key contains only the directed subject endpoint, directed object endpoint, and Graphiti-normalized statement. Predicate/relation, valid interval, and provenance are not part of that upstream key. The helper retains the first candidate and unions then deduplicates its episode candidate references exactly as the pinned fixture specifies.

Literal-candidate behavior and any deterministic tie-break not specified by the pinned Graphiti behavior are `documented_adaptation`, never `exact_upstream`. The compatibility fixture is authoritative if host-language text behavior differs.

After a caller allocates `FactAssertion.id`, identity is strict and no candidate merge rule applies. Reusing the same `FactId` requires a byte-identical canonical assertion; any difference, including provenance, returns `FactIdConflict`. Separate `FactId` values remain separate facts and proceed through explicit conflict, parallel-admission, or supersession rules. `MemoryGraph` never silently merges their assertions or provenance.

`ConflictDecision` records an actor, rationale, the candidate fact ID, the exact prior fact IDs considered, and an action:

```text
RejectCandidate
SupersedeExisting
AdmitParallel
```

Supersession is never inferred. `SupersedeFact` must list every old fact ID and pass all of these guards:

- candidate and old facts share `group_id`;
- they share the same subject;
- predicates match under the frozen normalization profile;
- entity-reference facts preserve the same directed endpoint structure, while literal facts preserve the same subject/predicate slot;
- their valid intervals overlap;
- each old fact is active immediately before the event;
- the decision lists exactly the old IDs supplied by the event.

These structural checks intentionally prevent unrelated facts from being invalidated, addressing the class of behavior described in Graphiti issue [#1728](https://github.com/getzep/graphiti/issues/1728). Fixtures for this stricter rule carry `parity_kind: documented_adaptation`.

`RetractFact` closes one fact's known-time visibility without changing its valid interval or source bytes. It rejects unknown or already inactive facts.

## MemoryGraph public surface

```text
MemoryGraph::new() -> MemoryGraph
MemoryGraph::apply(Self, Array[RecordedEvent]) -> Result[ApplyReport, MemoryError]
MemoryGraph::replay(Array[RecordedEvent]) -> Result[MemoryGraph, MemoryError]
MemoryGraph::query(Self, FactQuery) -> Result[Array[FactView], MemoryError]
MemoryGraph::history(Self, HistoryQuery) -> Result[Array[FactView], MemoryError]
MemoryGraph::diff(Self, DiffQuery) -> Result[FactDiff, MemoryError]
MemoryGraph::neighbors(Self, NeighborQuery) -> Result[Array[FactView], MemoryError]
MemoryGraph::explain(Self, FactId, valid_at: Timestamp, known_at: Timestamp) -> Result[ExplainReport, MemoryError]
MemoryGraph::plan_forget(Self, ForgetSelector, planned_at: Timestamp, reason: String) -> Result[ForgetPlan, MemoryError]
MemoryGraph::snapshot_events(Self) -> Array[RecordedEvent]
```

`RecordedEvent` contains `stream_id`, `seq`, `event_id`, `recorded_at`, and `event`. Its canonical event digest is derived, never caller-selected. A graph accepts one stream and rejects a mismatched `stream_id`, a non-increasing `seq`, or a decreasing `recorded_at` atomically.

### Query DTOs

`FactQuery` requires `valid_at` and `known_at`, with optional group, subject, predicate, object, provenance episode, ranked-candidate input, minimum score, and a bounded limit.

`HistoryQuery` requires a fact ID or a structured fact slot and a known-time range. It returns every visible version and closure marker in deterministic order.

`DiffQuery` requires one valid-time point and two known-time points, or one known-time point and two valid-time points. `FactDiff` contains stable `added`, `removed`, and `unchanged` arrays.

`NeighborQuery` requires a starting entity, `valid_at`, `known_at`, maximum BFS depth, direction (`Outgoing`, `Incoming`, or `Both`), optional predicate/group filters, and a result limit. A fact is traversable only when visible at both query times.

`FactView` contains the assertion, activation event/time, optional closing event/time, a score, and a stable explanation key. Public results are sorted by descending score, descending relevant time, then ascending fact ID. Ties never depend on map iteration.

`ExplainReport` contains the selected fact, source episodes and evidence, activation event, explicit supersession/retraction/forget chain, query times, score contributions, and any redaction markers. It never fabricates missing source text.

### Search helpers

The root package provides deterministic cosine similarity for equal-length finite vectors, BFS over the visible fact graph, and reciprocal-rank fusion (RRF). Invalid vector dimensions or non-finite values are errors. RRF uses an explicit positive `k` and stable candidate-ID tie breaking.

Embedding and BM25 implementations are outside v1. They integrate through:

```text
RankedCandidate
  fact_id: FactId
  rank: Int
  score: Double?
  source: String

RankedCandidateList
  candidates: Array[RankedCandidate]
```

The DTO is synchronous data. No async `Embedder` API is frozen in v1.

## Forget contract

`ForgetSelector` is one explicit selector:

```text
Fact(FactId)
Episode(EpisodeId)
Entity(EntityId)
Group(GroupId)
RecordedBefore(Timestamp)
```

`plan_forget` resolves the selector against the current graph and returns an immutable `ForgetPlan` containing:

- plan digest and planning timestamp supplied by the caller;
- selector and non-empty reason;
- source semantic-state digest;
- sorted exact affected episode, entity, fact, and event IDs;
- sorted exact dependent fact IDs reached through provenance or entity endpoints.

Planning performs the only traversal. Applying the plan verifies its source state and appends `ApplyForgetPlan`; it never recomputes a dynamic cascade. A stale plan fails without mutation. Normal query projection hides forgotten material, while history and explain retain redaction-aware audit markers.

## Canonical JSONL

`codec/jsonl` exposes:

```text
encode_event(EventEnvelope) -> Result[String, MemoryError]
decode_event(String) -> Result[EventEnvelope, MemoryError]
encode_jsonl(Array[EventEnvelope]) -> Result[String, MemoryError]
decode_jsonl(String) -> Result[Array[EventEnvelope], MemoryError]
```

Each line uses this versioned top-level field order:

```text
schema_version
stream_id
seq
event_id
recorded_at_ms
prev_hash
event
event_hash
```

Canonicalization is UTF-8 without BOM, one LF after every record, no insignificant whitespace, integer millisecond times, fixed object-field order, lexicographically sorted set-like arrays, and deterministic string escaping. A CRLF input is decoded only through an explicit import normalization path; the canonical decoder rejects noncanonical line endings. Unknown schema versions, unknown event variants, duplicate object keys, corrupt lines, non-increasing sequence values, decreasing record times, broken hashes, and a truncated final record are errors.

`event_hash` is lowercase SHA-256 over the domain prefix `FactEpoch/event/v1\n`, the previous hash, and the canonical envelope excluding `event_hash`. The first `prev_hash` is 64 zeroes. `moonbitlang/x@0.5.1` supplies the pure-MoonBit SHA-256 implementation; NIST and Python vectors verify behavior for ASCII, Chinese text, emoji, and canonicalized line endings.

The root package owns canonical semantic-state serialization and passes those bytes to the low-level integrity SHA primitives when producing `ApplyReport`. `codec/jsonl` similarly owns event serialization, while `compact` owns artifact and redaction-set serialization. The integrity package knows none of these root types; it only computes domain-separated SHA-256 over bytes. Hashes are consistency evidence, not authentication.

## Compaction contract

```text
compact(input, output, policy, expected_head) -> Result[CompactionReceipt, MemoryError]
verify(artifact, expected_receipt?) -> Result[VerificationReport, MemoryError]
```

`compact` never overwrites its input, never accepts the same resolved input/output path, never auto-deletes an input, and rejects an existing destination. It writes a sibling temporary file, flushes and synchronizes it where the platform exposes that operation, closes it, reads it back, verifies it, and only then publishes a new immutable generation. The guarantee is conditional on the host filesystem; no claim is made about directory fsync or hostile concurrent writers.

`Preserve` retains all observable history. `Redact` removes the bodies of confirmed forgotten episodes/entities/facts from the new artifact, retains their digests and redacted markers, and proves that the unforgotten state projection matches the source. Neither policy changes the source artifact.

`CompactionReceipt` records:

- schema and canonicalization versions;
- stream ID, generation ID, and through-sequence;
- source path label, event count, chain-head digest, and whole-file digest;
- before and after semantic-state digests;
- output artifact digest;
- retained and pruned counts by record kind;
- redaction-set digest;
- policy and publication result.

A receipt cannot prove secure erasure. Redacted bodies may remain in the original journal, backups, logs, caches, temporary files, or storage media.

## Extraction boundary

`extract/api` defines an async `Extractor` returning a strict `ExtractionBatch`. A batch contains entity candidates, fact candidates, evidence spans, confidence values, and source correlation data. It cannot contain official IDs, `recorded_at`, sequence numbers, hashes, retraction targets, supersession targets, or a write command. Callers validate candidates and construct events explicitly.

`extract/fixture` is the deterministic offline implementation used by tests and examples.

`extract/openai_compat` uses `moonbitlang/async@0.21.2`, is native-only, and supports one non-streaming Chat Completions-compatible POST shape. Construction requires an explicit endpoint, model, environment-variable name for the Bearer token, timeout, and size limits. Requests use `temperature: 0` and strict JSON output. The adapter does not implement streaming, tool calling, embeddings, retries, endpoint discovery, provider-specific URL rewriting, or a multi-vendor SDK.

Transport, timeout, HTTP status, malformed response, invalid extraction, and limit errors return zero graph writes. Diagnostics redact tokens and authorization headers. Tests inject a transport or local fake service and never call a real model endpoint.

## Errors and reports

`MemoryError` has stable categories for invalid identifiers/time/intervals, missing references, endpoint/group mismatch, duplicate conflicts, event-ID conflicts, stale decisions/plans, atomic batch rejection, query limits, JSON/schema/canonicalization failures, sequence/hash failures, truncation, vector errors, I/O publication failures, extractor transport/timeout/HTTP/malformed/limit errors, and history unavailable after redaction.

`ApplyReport` currently contains defensively copied accepted and idempotent event IDs, created episode/entity/fact counts, and the resulting event count. It is returned only for a successful atomic batch. A semantic-state digest will be added only after the canonical state encoding and integrity package define the exact bytes covered; the current API does not return a placeholder digest.

## Examples that define acceptance

The offline examples will cover:

1. `profile_drift`: a user preference changes and both former and current answers remain queryable.
2. `repo_decisions`: a coding decision is superseded, a late record changes an old valid-time answer, and explain traces the source episode.
3. `support_case`: a plan and ticket correction demonstrates the `valid_at × known_at` matrix.

Each example will be executable in CI with fixed IDs and timestamps.
