# Ecosystem Differentiation

Last reviewed: 2026-09-05.

This survey asks whether FactEpoch would duplicate a mature Mooncakes project. The comparison uses published package pages and focuses on explicit public contracts, not presumed implementation gaps.

## Decision criteria

A highly overlapping project would already make all of these its central contract:

1. mandatory `valid_at` and `known_at` point queries;
2. late-arriving historical facts without retroactive system knowledge;
3. explicit fact version, supersession, and retraction events;
4. episode-level provenance and explanations;
5. deterministic replay from a versioned event format;
6. frozen forget plans and non-in-place redaction artifacts.

## Surveyed packages

| Package | Relevant published area | Relationship to FactEpoch |
| --- | --- | --- |
| [Across2005/MoonBit-memory](https://mooncakes.io/docs/Across2005/MoonBit-memory) | Memory-management utilities | Different layer: runtime memory mechanics rather than a temporal fact ledger. |
| [mizchi/mnemo](https://mooncakes.io/docs/mizchi/mnemo) | Memory-oriented utilities | Adjacent theme; FactEpoch is defined by the bitemporal event/query contract. |
| [weopqrst/agent](https://mooncakes.io/docs/weopqrst/agent) | Agent components | Potential consumer or peer; FactEpoch does not orchestrate an agent. |
| [niuniu513-ask/MoonRetrieve](https://mooncakes.io/docs/niuniu513-ask/MoonRetrieve) | Retrieval | Complementary: its ranked output could cross FactEpoch's candidate DTO boundary. |
| [trkbt10/vcdb](https://mooncakes.io/docs/trkbt10/vcdb) | Vector storage/search | Complementary infrastructure; FactEpoch intentionally excludes a vector database. |
| [Across2005/yimai_prophecy_moonbit](https://mooncakes.io/docs/Across2005/yimai_prophecy_moonbit) | Memory/prediction workflow | Closest reviewed project, but FactEpoch's planned deliverable is the narrower auditable bitemporal kernel described by the six criteria above. |

The table does not grade those packages and does not assert that their internal or future behavior cannot overlap. Before publication, maintainers will rerun these keyword searches on Mooncakes: `memory`, `agent memory`, `temporal`, `bitemporal`, `fact graph`, `knowledge graph`, `provenance`, `episode`, `forget`, and `Graphiti`.

## Value beyond the first demo

The kernel is intended to serve several domains without embedding domain rules:

- personal preference history;
- code-agent decisions and later corrections;
- support-plan and ticket histories;
- compliance evidence timelines;
- configuration and policy evolution;
- reproducible evaluation of memory extraction systems.

Expansion happens through application schemas, ranked-candidate producers, and storage adapters rather than by weakening the temporal contract.

The implemented Graphiti candidate helper is an interoperability boundary, not the product thesis: it prepares extracted entity-reference candidates before authoritative IDs and time are allocated while preserving every Episode source as an explicit adaptation.

## Re-evaluation rule

If a maintained Mooncakes package is found to expose the six core criteria, the project will document whether to collaborate, depend on it, narrow scope further, or stop duplicative work. The README will not preserve a differentiation claim contradicted by current evidence.
