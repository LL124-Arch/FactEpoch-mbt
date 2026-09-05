# Compatibility Policy

FactEpoch v1 will stabilize behavior in three layers.

## Public MoonBit API

The root package is the public owner. Once `v0.1.0` is released, changes to public names, argument meaning, error categories, result ordering, or generated interfaces are documented in `CHANGELOG.md`. A breaking change requires a versioned migration note.

The portable core must continue to check and test on `wasm`, `wasm-gc`, `js`, and `native`. Native CLI, filesystem, and HTTP packages are explicitly outside cross-target compatibility.

## Event protocol

Canonical JSONL v1 is strict. `schema_version`, field order, UTF-8/LF rules, integer-millisecond encoding, event variants, domain-separated hashes, and sorting rules are protocol behavior. Decoders reject unknown versions rather than guessing.

Changing canonical bytes or event meaning requires a new schema version, an ADR, fixtures for both versions, and an explicit migration command. A newer decoder must not silently reinterpret a v1 journal.

## Graphiti relationship

Compatibility means fixture-level parity with Graphiti `0.30.1` at commit `547422865cca9fb5a82915c074d899428c145ff4` only for behaviors labeled `exact_upstream`. In v1 that covers directed subject/object endpoints, statement normalization, and first-candidate retention for pre-ID entity-reference candidates. The normalization oracle is fixed to CPython `3.12.14`, UCD `15.0.0`, `str.lower()`, and Python Unicode `\s+` collapse/strip; no casefold or NFC/NFD normalization is implied. Predicate/relation, confidence, interval, and provenance are not key fields.

Search fixtures additionally label the well-formed cosine and RRF formulas, empty/zero-norm cosine behavior, and inclusive RRF threshold as `exact_upstream`. Source uniqueness, rank validation, finite-arithmetic errors, canonical source/rank accumulation, and fact-ID tie breaking are `documented_adaptation`. Ranked temporal joins and BFS are FactEpoch APIs, not Graphiti compatibility surfaces.

Graphiti does not union episode references in this path. FactEpoch's sorted Episode union, member-ID record, explicit group component, and literal pass-through are `documented_adaptation`. After official IDs exist, FactEpoch uses strict canonical `FactId` identity and explicit conflict rules rather than upstream candidate merging. FactEpoch does not promise parity with other Python/Unicode profiles, nor Python API, database schema, wire protocol, or operational compatibility with Graphiti.

An entity-reference output reports both `ExactUpstream` and `DocumentedAdaptation` in a fixed array: exact normalization/directed-key/first-retention semantics coexist with FactEpoch's group component. A merged class remains dual-labeled because membership and Episode union are adaptations. Literal outputs report only `DocumentedAdaptation`.

`factepoch import graphiti` will be a documented conversion path for supported fixture/export shapes, not a general Graphiti database migration tool. Unsupported fields must produce diagnostics rather than being silently discarded.

## Reproducibility

Committed JSON fixtures, their strict Python oracles, generated MoonBit fixture tests, generated MoonBit interfaces, and release audit commands are the compatibility evidence. The normalization oracle fixes its Python/Unicode profile, while the numeric search oracle checks only stable finite formulas. Both reject metadata drift; the search oracle also deterministically renders the complete generated search test from executable fixture inputs/expectations and byte-compares it under `--check`. The exact Graphiti first-seen tie is verified only by the Python oracle because FactEpoch deliberately uses its documented FactId tie rule. Live model output and benchmark speed are not compatibility contracts.
