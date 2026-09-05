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

### Documentation

- Established the pure-MoonBit bitemporal fact-graph scope and explicit non-goals.
- Pinned the Graphiti semantic reference to release `0.30.1`, commit `547422865cca9fb5a82915c074d899428c145ff4`.
- Defined repository, licensing, security, contribution, roadmap, and third-party policies.
- Added a test-driven, outcome-based implementation plan without claiming any runtime capability.
- Recorded the implemented projection model, ASCII predicate-key profile, and immutable future closure semantics in ADR 0002.

No software version has been released.
