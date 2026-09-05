# FactEpoch-mbt

[简体中文](README.zh-CN.md)

> **Status: foundation API available.** The portable root package now provides validated IDs, UTC Unix-millisecond timestamps, half-open intervals, canonical metadata, provenance/evidence types, domain constructors, and an empty `MemoryGraph`. Event application, bitemporal queries, journals, compaction, CLI programs, extractors, and releases are not implemented yet.

FactEpoch-mbt is a pure-MoonBit bitemporal fact-graph kernel under active development for agent memory. It records when a fact is valid in the modeled world, when the system learned it, which episode supplied it, and which explicit event replaced or retracted it. The kernel is deliberately smaller than a complete agent framework, conversation cache, vector store, or graph database.

The first release is intended for applications that need answers to both of these questions:

- What did we believe on 18 September about the user's preference on 12 September?
- What do we know now about that same point in the past, after a late correction arrived?

That distinction is the reason for the project. A single `updated_at` field cannot answer both questions without erasing history.

The checked foundation example is in [the quickstart](docs/quickstart.mbt.md). From the repository root:

```text
moon check --target all
moon test --target all
moon test docs --target all
```

## v1 contract under implementation

- UTC Unix millisecond timestamps and half-open valid intervals `[valid_from, valid_to)`.
- Every query supplies both `valid_at` and `known_at`.
- Caller-supplied identifiers and event times in the portable core; only the CLI reads the clock and allocates monotonic sequence numbers.
- Batch prevalidation: `MemoryGraph::apply` either accepts the complete batch or leaves the graph unchanged.
- Idempotent replay for the same event ID and byte-identical payload; the same ID with a different payload is an error.
- Explicit supersession and retraction. A model cannot silently invalidate a fact.
- Episode-to-fact provenance, deterministic history, stable score/time/ID ordering, BFS, cosine scoring, and reciprocal-rank fusion.
- Versioned canonical JSONL with SHA-256 event chaining, semantic-state digests, and artifact digests.
- Logical forgetting through a frozen plan, followed by optional non-in-place preserve or redact compaction.
- Portable core packages for `wasm`, `wasm-gc`, `js`, and `native`.
- An offline fixture extractor plus a separately gated native OpenAI-compatible adapter.

The public surface and its invariants are frozen in [the design contract](docs/design.md). Implemented portions are covered by tests on `wasm`, `wasm-gc`, `js`, and `native`; future-looking items above remain roadmap commitments rather than current capability claims.

## Product boundary

FactEpoch owns temporal fact semantics, not storage infrastructure or agent orchestration. Version 1 will not include Neo4j, FalkorDB, Kuzu, Neptune, SQLite, an ANN or BM25 database, a complete Graphiti API, dynamic ontologies, communities, MCP, REST, a Web UI, or a multi-provider model SDK.

External embedding or BM25 systems can submit already ranked candidate IDs through a small DTO. They do not become dependencies of the kernel. The core never reads system time, environment variables, files, databases, or the network.

## Why another MoonBit memory package?

The Mooncakes ecosystem already has useful memory, agent, retrieval, and vector-storage projects. FactEpoch is scoped around a different invariant: reconstructing fact versions on both valid time and system-known time while retaining the source episode and explicit replacement chain.

| Project | Published focus | FactEpoch's intended distinction |
| --- | --- | --- |
| [MoonBit-memory](https://mooncakes.io/docs/Across2005/MoonBit-memory) | Memory-management utilities | FactEpoch models durable temporal facts and provenance, not allocation or runtime memory management. |
| [mnemo](https://mooncakes.io/docs/mizchi/mnemo) | Memory-oriented utilities | FactEpoch's contract is a bitemporal event ledger with historical reconstruction. |
| [agent](https://mooncakes.io/docs/weopqrst/agent) | Agent building blocks | FactEpoch is an embeddable memory kernel, not an agent runtime. |
| [MoonRetrieve](https://mooncakes.io/docs/niuniu513-ask/MoonRetrieve) | Retrieval components | FactEpoch can consume ranked candidates, but its primary job is temporal truth-state reconstruction. |
| [vcdb](https://mooncakes.io/docs/trkbt10/vcdb) | Vector-oriented storage/search | FactEpoch does not ship a vector database; it supplies filtering, graph traversal, and deterministic rank fusion over supplied candidates. |
| [yimai_prophecy_moonbit](https://mooncakes.io/docs/Across2005/yimai_prophecy_moonbit) | Memory and prediction workflow | This is the closest overlap surveyed. FactEpoch narrows its claim to explicit `valid_at × known_at` queries, versioned facts, source episodes, and auditable supersession. |

These are scope comparisons based on the linked package pages, not quality judgments or claims that another project can never support similar behavior. [The differentiation note](docs/differentiation.md) records the comparison criteria and review date.

## Selective Graphiti migration

The semantic reference is [Graphiti](https://github.com/getzep/graphiti) `0.30.1` at commit [`547422865cca9fb5a82915c074d899428c145ff4`](https://github.com/getzep/graphiti/tree/547422865cca9fb5a82915c074d899428c145ff4). FactEpoch will selectively translate deterministic data-model, temporal, pre-ID candidate-deduplication, and ranking behavior from Python into idiomatic MoonBit. Upstream-exact dedup is limited to group-scoped entity-reference candidates using directed endpoints and normalized statement; authoritative `FactId` values are never silently merged. FactEpoch is not a full port and will not offer drop-in API compatibility.

Graphiti issue [#1728](https://github.com/getzep/graphiti/issues/1728) documents an unrelated-fact invalidation failure mode. FactEpoch therefore requires superseded facts to match the same group, subject, and predicate/endpoint structure. That stricter behavior is recorded as `documented_adaptation`, not represented as exact upstream parity.

No Graphiti implementation source is present in this baseline. Future translated files must carry the header policy in [THIRD_PARTY.md](THIRD_PARTY.md), and parity fixtures must name the upstream commit and whether they are `exact_upstream` or `documented_adaptation`.

## Target repository layout

```text
FactEpoch-mbt/
├── README.md / README.zh-CN.md
├── LICENSE / NOTICE / THIRD_PARTY.md
├── CHANGELOG.md / ROADMAP.md
├── CONTRIBUTING.md / SECURITY.md
├── moon.mod / moon.pkg
├── *.mbt
├── codec/jsonl/
├── integrity/
├── compact/
├── extract/{api,fixture,openai_compat}/
├── cmd/{factepoch,factepoch-openai-demo}/
├── examples/{profile_drift,repo_decisions,support_case}/
├── compat/python/
├── fixtures/graphiti/
├── bench/
├── docs/
│   ├── quickstart.mbt.md
│   ├── architecture.md
│   ├── upstream.md
│   ├── differentiation.md
│   ├── compatibility.md
│   ├── limitations.md
│   └── decisions/
└── .github/workflows/ci.yml
```

There is one `moon.mod`. The root package owns public domain types and the portable graph API, avoiding circular dependencies and re-export ambiguity.

## Planned command line

```text
factepoch init
factepoch episode add
factepoch entity put
factepoch fact assert|supersede|retract
factepoch query current|at|as-known-at
factepoch history|diff|neighbors|explain
factepoch forget plan|apply
factepoch compact|verify|doctor
factepoch import graphiti
factepoch export
```

`factepoch-openai-demo` will be an explicit opt-in native executable. It will not be part of the normal offline workflow.

## Integrity and privacy limits

SHA-256 receipts can demonstrate that bytes and projections match a stated digest; they do not authenticate a writer or resist an attacker who can replace both an artifact and its expected digest. Redact compaction will exclude confirmed forgotten bodies from a new artifact, but it cannot erase the source journal, backups, caches, or storage remnants. See [SECURITY.md](SECURITY.md) and [limitations](docs/limitations.md).

## Documentation

- [Design contract](docs/design.md)
- [Architecture](docs/architecture.md)
- [Implementation plan](docs/implementation-plan.md)
- [Upstream mapping and attribution](docs/upstream.md)
- [Differentiation](docs/differentiation.md)
- [Compatibility policy](docs/compatibility.md)
- [Known limitations](docs/limitations.md)
- [Quickstart status](docs/quickstart.mbt.md)
- [ADR 0001: scope and upstream](docs/decisions/0001-scope-and-upstream.md)

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing protocol behavior. FactEpoch-mbt is licensed under the [Apache License 2.0](LICENSE). Third-party provenance is recorded in [NOTICE](NOTICE) and [THIRD_PARTY.md](THIRD_PARTY.md).
