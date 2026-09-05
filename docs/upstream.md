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
| Entity-edge candidate deduplication | root `CandidateFact`, `deduplicate_candidates`, and fixtures | `exact_upstream` for directed endpoints, pinned statement normalization, and first retention; provenance preservation and group isolation are adaptations. |
| Temporal validity | root interval and replay logic | Selective translation, extended with mandatory bitemporal queries. |
| Edge invalidation/supersession | root `ConflictDecision` and `SupersedeFact` | `documented_adaptation` with stricter group and structural guards. |
| Search result ordering and rank fusion | root ranked DTO, cosine, BFS and RRF | Deterministic translation with stable ID tie-breaking. |
| Database persistence | no mapping | Not ported. Canonical JSONL is a FactEpoch design. |
| LLM extraction orchestration | `extract/api` and thin native adapter | Replaced by a strict candidate-only boundary. |

## Parity labels

Every compatibility fixture includes:

```text
fixture_schema
parity_kind
upstream (repository, version, commit)
runtime_profile (implementation, version, ucd_version) when text behavior is exact
normalization_source and dedup_source (path and symbol)
named input/expected cases or a non-empty adaptation reason
```

`parity_kind` is exactly one of:

- `exact_upstream`: the expected deterministic result is intended to match the pinned Python behavior;
- `documented_adaptation`: FactEpoch deliberately differs and the fixture states why.

The Python oracle is development and drift-check tooling under `compat/python`; Python is not a runtime dependency.

The fixture-level `parity_kind` labels the fixture's purpose. A `DeduplicatedCandidate` exposes a canonical `parity_kinds` array because one result can simultaneously exercise upstream normalization/first retention and FactEpoch's explicit group isolation. Entity-reference results use `[ExactUpstream, DocumentedAdaptation]`; literal results use `[DocumentedAdaptation]`. The getter returns a defensive copy.

## Candidate deduplication boundary

The helper runs before FactEpoch allocates authoritative fact IDs. For entity-reference candidates it compares directed subject/object endpoints and the Graphiti-normalized statement; predicate/relation, confidence, valid interval, and provenance are not key fields. Exact normalization is pinned to Graphiti `0.30.1` on CPython `3.12.14` with UCD `15.0.0`: `str.lower()` followed by Python Unicode `\s+` collapse and strip. It does not casefold or normalize NFC/NFD.

Upstream retains the first candidate and does not union Episode references. FactEpoch additionally places `GroupId` in the operational key, records all member candidate IDs, and unions/sorts/deduplicates source Episode IDs. Those changes prevent cross-tenant matching and provenance loss and are `documented_adaptation` rather than `exact_upstream`.

Literal candidates pass through individually and are labeled `documented_adaptation`. Once candidates become formal `FactAssertion` values, Graphiti candidate merging no longer applies: the same `FactId` must have byte-identical canonical content or fail with `FactIdConflict`, and separate IDs remain explicit facts whose conflicts require explicit decisions.

## Directly adapted files

The current translated/modified source mapping is:

| Upstream source | MoonBit destination | Scope |
| --- | --- | --- |
| `graphiti_core/utils/maintenance/dedup_helpers.py::_normalize_string_exact` | `graphiti_normalize.mbt` | Candidate statement normalization, with generated fixed-profile Unicode tables. |
| `graphiti_core/utils/maintenance/edge_operations.py::resolve_extracted_edges` | `graphiti_candidate_dedup.mbt` | Directed entity-reference candidate key and first retention, with documented FactEpoch adaptations. |
| both symbols above | `compat/python/oracle_graphiti_v0301.py` | Strict fixture validator and generated MoonBit-vector producer; adapted development tooling only. |

The MoonBit files carry this leading notice:

```text
SPDX-License-Identifier: Apache-2.0
Portions derived from getzep/graphiti.
Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
Copyright 2024, Zep Software, Inc.
Translated and modified for MoonBit in 2026.
```

The Python oracle uses the same first four attribution lines and an `Adapted as a fixture oracle` final line, accurately describing its role.

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
