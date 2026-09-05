# Compatibility Policy

FactEpoch v1 will stabilize behavior in three layers.

## Public MoonBit API

The root package is the public owner. Once `v0.1.0` is released, changes to public names, argument meaning, error categories, result ordering, or generated interfaces are documented in `CHANGELOG.md`. A breaking change requires a versioned migration note.

The portable core must continue to check and test on `wasm`, `wasm-gc`, `js`, and `native`. Native CLI, filesystem, and HTTP packages are explicitly outside cross-target compatibility.

## Event protocol

Canonical JSONL v1 is strict. `schema_version`, field order, UTF-8/LF rules, integer-millisecond encoding, event variants, domain-separated hashes, and sorting rules are protocol behavior. Decoders reject unknown versions rather than guessing.

Changing canonical bytes or event meaning requires a new schema version, an ADR, fixtures for both versions, and an explicit migration command. A newer decoder must not silently reinterpret a v1 journal.

## Graphiti relationship

Compatibility means fixture-level parity with Graphiti `0.30.1` at commit `547422865cca9fb5a82915c074d899428c145ff4` only for behaviors labeled `exact_upstream`. In v1 that label covers the pre-ID, group-scoped entity-reference candidate helper: directed subject/object endpoints plus Graphiti-normalized statement, first-candidate retention, and episode-candidate-reference union/deduplication. Predicate/relation, interval, and provenance are not key fields. Literal candidates and added tie-breaks are `documented_adaptation`. After official IDs exist, FactEpoch uses strict canonical `FactId` identity and explicit conflict rules rather than upstream candidate merging. FactEpoch does not promise Python API, database schema, wire protocol, or operational compatibility with Graphiti.

`factepoch import graphiti` will be a documented conversion path for supported fixture/export shapes, not a general Graphiti database migration tool. Unsupported fields must produce diagnostics rather than being silently discarded.

## Reproducibility

Committed golden fixtures, generated MoonBit interfaces, and release audit commands are the compatibility evidence. Live model output and benchmark speed are not compatibility contracts.
