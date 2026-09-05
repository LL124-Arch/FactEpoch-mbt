# Upstream Mapping

## Pinned reference

- Project: [getzep/graphiti](https://github.com/getzep/graphiti)
- Version: `0.30.1`
- Commit: [`547422865cca9fb5a82915c074d899428c145ff4`](https://github.com/getzep/graphiti/tree/547422865cca9fb5a82915c074d899428c145ff4)
- Upstream license: Apache License 2.0
- Upstream copyright used for adapted-file notices: `Copyright 2024, Zep Software, Inc.`

The commit pin is the only upstream baseline for v1 parity fixtures. A later Graphiti release does not silently change FactEpoch behavior.

## Python-to-MoonBit mapping

| Graphiti concept | FactEpoch location | Treatment |
| --- | --- | --- |
| Episodes as source records | root `Episode` and `Provenance` | Selective translation; storage-specific fields are omitted. |
| Entity nodes | root `Entity` | Selective translation into a deterministic, database-independent record. |
| Entity-edge candidate deduplication | pre-ID compatibility helper and fixtures | `exact_upstream` for the pinned group-scoped directed-endpoint and normalized-statement behavior. |
| Temporal validity | root interval and replay logic | Selective translation, extended with mandatory bitemporal queries. |
| Edge invalidation/supersession | root `ConflictDecision` and `SupersedeFact` | `documented_adaptation` with stricter group and structural guards. |
| Search result ordering and rank fusion | root ranked DTO, cosine, BFS and RRF | Deterministic translation with stable ID tie-breaking. |
| Database persistence | no mapping | Not ported. Canonical JSONL is a FactEpoch design. |
| LLM extraction orchestration | `extract/api` and thin native adapter | Replaced by a strict candidate-only boundary. |

## Parity labels

Every compatibility fixture includes:

```text
upstream_repository
upstream_version
upstream_commit
source_module
source_symbol
parity_kind
input
expected
```

`parity_kind` is exactly one of:

- `exact_upstream`: the expected deterministic result is intended to match the pinned Python behavior;
- `documented_adaptation`: FactEpoch deliberately differs and the fixture states why.

The Python oracle is development and drift-check tooling under `compat/python`; Python is not a runtime dependency.

## Candidate deduplication boundary

The `exact_upstream` helper runs before FactEpoch allocates authoritative fact IDs. Within one group-scoped entity-reference candidate set, it compares only directed subject/object endpoints and the Graphiti-normalized statement. Predicate/relation, valid interval, and provenance are not part of this upstream key. It retains the first candidate and unions/deduplicates episode candidate references as the pinned fixture specifies.

Literal candidates and deterministic tie-breaking beyond the pinned behavior are labeled `documented_adaptation`. Once candidates become formal `FactAssertion` values, Graphiti candidate merging no longer applies: the same `FactId` must have byte-identical canonical content or fail with `FactIdConflict`, and separate IDs remain explicit facts whose conflicts require explicit decisions.

## Directly adapted files

No Graphiti source has been translated into the current design-only baseline. If a future file contains translated or structurally derived implementation, its leading comment must include:

```text
SPDX-License-Identifier: Apache-2.0
Portions derived from getzep/graphiti.
Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
Copyright 2024, Zep Software, Inc.
Translated and modified for MoonBit in 2026.
```

The same change must update this page with the upstream source path and translated destination path. Merely learning a public algorithm or writing an independent test does not justify claiming verbatim source reuse, but the conceptual source remains documented here.

## Deliberate adaptation for issue 1728

[Graphiti issue #1728](https://github.com/getzep/graphiti/issues/1728) describes unrelated edges being invalidated during edge processing. FactEpoch makes supersession explicit and validates that every old fact shares the candidate's group, subject, predicate, and directed endpoint/slot structure. A mismatch rejects the entire batch.

This guard is a `documented_adaptation`. It must never be reported as an upstream bug fix incorporated by Graphiti unless the pinned upstream commit actually contains equivalent behavior.

## Not ported

The following Graphiti areas are outside v1:

- Neo4j, FalkorDB, Kuzu, Neptune, and other database drivers;
- service APIs, queues, background workers, and deployment configuration;
- full-text and vector database implementations;
- community construction and dynamic ontology machinery;
- complete Graphiti client or server API compatibility;
- provider-specific LLM and embedding integrations.

FactEpoch is therefore a selective migration, not a fork, replacement, or drop-in implementation of Graphiti.
