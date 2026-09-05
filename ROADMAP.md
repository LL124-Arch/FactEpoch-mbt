# Roadmap

**Project status: Implementation in progress.** The repository begins with a documentation and policy baseline. Every capability below remains planned until its tests, implementation, generated interface review, and changelog entry land together.

## Foundation

- Establish MoonBit module metadata and focused package boundaries.
- Define public fact, interval, provenance, identifier, event, and query types in the public owner package.
- Record public interfaces through committed `pkg.generated.mbti` files.

## Deterministic integrity layer

- Implement interval algebra and strict timestamp normalization.
- Implement canonical JSON encoding with golden cross-target fixtures.
- Implement pure-MoonBit SHA-256 and hash-chain construction.
- Add append-only journal verification, corruption diagnostics, and crash-safe append behavior.

## Bitemporal graph semantics

- Replay journal events into deterministic indexes.
- Support `valid_at` plus `known_at` point queries and deterministic ordering.
- Enforce explicit conflict guards before acceptance.
- Support logical retraction and explicit conflict-resolution records.
- Compact into a separate destination artifact with verifiable lineage.

## Ingestion boundaries

- Ship synthetic, deterministic offline extraction fixtures as the default integration path.
- Add an optional native-only OpenAI-compatible adapter with disabled-by-default networking, bounded responses, strict parsing, and secret-safe diagnostics.
- Prove that offline tests and core packages remain independent of the network adapter.

## Hardening and release readiness

- Add property, corruption, recovery, cross-target determinism, and resource-limit tests.
- Audit dependency licenses and update `THIRD_PARTY.md` with every adopted package.
- Publish a stable public API only after `moon info` review and an end-to-end reproducibility run.
- Create the first release only when the documented security and integrity limitations are reflected in user-facing API documentation.

## Permanent non-goals

FactEpoch-mbt does not plan to become a hosted graph database, a UI, a vector database, a generic agent framework, an autonomous truth arbiter, or a distributed consensus system. It will not require online model access for normal operation and will not perform destructive history rewriting or in-place compaction.

The executable order and acceptance evidence are detailed in the [implementation plan](docs/implementation-plan.md).
