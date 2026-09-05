# Changelog

All notable changes to FactEpoch-mbt will be documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and released versions will use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Added the `LL124-Arch/factepoch` MoonBit module and portable root package.
- Added opaque checked identifiers, signed Unix-millisecond timestamps, and half-open valid intervals.
- Added canonical metadata, UTF-8 evidence validation, provenance normalization, and validated episode, entity, and fact constructors.
- Added an executable foundation quickstart and all-target tests for the public surface.
- Added caller-stamped episode, entity, and fact events with strict stream, sequence, and recorded-time ordering.
- Added atomic batch application, exact event idempotence, strict domain-ID conflict detection, reference/group validation, deterministic snapshots, and replay.
- Added staged ID indexes for bounded lookup work while retaining insertion-ordered arrays as the observable event order.
- Preserved each fact's first activation event and time in a private lifecycle record ready for explicit closure events.
- Added activation-only bitemporal query with group, subject, normalized predicate, exact object, and provenance-episode filters.
- Added closed-window activation history by fact identity or normalized fact slot, plus diffs across known time or valid time.
- Added stable confidence/valid-time/fact-ID ordering, bounded read limits, defensive result arrays, and replay-equivalent projections.
- Added opaque pre-ID candidate values, deterministic Graphiti-compatible entity-reference matching, and caller-controlled fact materialization.
- Preserved every duplicate candidate's Episode sources as a documented adaptation while retaining the first candidate's fact fields.
- Added a generated CPython 3.12.14/UCD 15.0.0 lowercase profile, exact/adaptation fixtures, and Python drift checks without adding a runtime dependency.
- Generated MoonBit parity tests directly from strictly validated fixtures, including contextual sigma, compressed-run gaps, non-BMP lowercase, and all pinned whitespace data.
- Made result parity compositional: entity-reference candidates report both exact upstream behavior and explicit group/provenance adaptations, while literals report adaptation only.
- Added canonical external ranked-candidate DTOs, deterministic reciprocal-rank fusion, safe cosine similarity, and closure-aware `query_ranked`.
- Added bounded directional BFS with Literal leaves, filtered traversal, minimum-depth deduplication, and stable depth/confidence/time/ID ordering.
- Added pinned Graphiti search fixtures and a strict CPython renderer/oracle that separates exact formulas from deterministic safety adaptations and byte-checks the generated MoonBit tests.

### Documentation

- Established the pure-MoonBit bitemporal fact-graph scope and explicit non-goals.
- Pinned the Graphiti semantic reference to release `0.30.1`, commit `547422865cca9fb5a82915c074d899428c145ff4`.
- Defined repository, licensing, security, contribution, roadmap, and third-party policies.
- Added a test-driven, outcome-based implementation plan without claiming any runtime capability.
- Recorded the implemented projection model, ASCII predicate-key profile, and the then-future immutable closure semantics in ADR 0002.
- Added immutable conflict decisions, explicit supersession and retraction events, one terminal closure per fact, and atomic multi-fact structural guards.
- Made query, closed-window history, and both diff axes closure-aware while preserving known-time prefix replay.
- Added `MemoryGraph::explain` with visibility categories, source episodes, and a defensive, knowledge-bounded lifecycle chain.
- Recorded the implemented terminal-closure trade-off in ADR 0003.

No software version has been released.
