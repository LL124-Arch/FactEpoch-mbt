# Security policy

## Supported versions

FactEpoch-mbt has no released or production-supported version. The repository now contains a tested foundation API for identifiers, time intervals, metadata, provenance, and domain construction, but it does not yet implement the event ledger or bitemporal query engine and must not be treated as deployable software.

Security support will begin with the first published release. At that point this section will identify supported version lines using actual release identifiers.

## Reporting a vulnerability

Do not place exploit details, credentials, private facts, prompts, or model responses in a public issue. When repository hosting provides private security advisories, use that private channel. Before such a channel exists, contact the maintainer only through an already trusted private channel and retain sensitive evidence locally; do not send secrets merely to demonstrate impact.

Include a concise impact description, affected version or commit, reproduction conditions, and the smallest sanitized proof necessary. Remove tokens, personal data, proprietary source text, and unrelated journal records. The maintainer will acknowledge and prioritize reports according to reproducibility and impact; this policy does not promise a fixed response or release deadline.

## Security boundary

The implemented foundation covers deterministic validation of identifiers, intervals, metadata, provenance, and domain values. The planned trusted core extends that boundary to canonical serialization, hash-chain verification, journal replay, bitemporal queries, conflict guards, logical retraction, and non-in-place compaction. Its guarantees are deliberately narrow:

- A valid hash chain can reveal byte-level modification, truncation when an expected head is known, reordering, or broken ancestry.
- It does not prove that a statement is true, that a source is trustworthy, or that the original writer was authorized.
- It provides integrity, not confidentiality. JSONL journals must be protected with operating-system access control and, when required, storage-level encryption.
- Logical retraction preserves historical bytes. It is not a secure-erasure mechanism and cannot satisfy a deletion request by itself.
- Non-in-place compaction creates another artifact; operators remain responsible for retention and secure deletion of superseded files.

## Threats the implementation must address

- malformed, oversized, deeply nested, duplicate-key, or non-canonical JSON input;
- invalid or ambiguous timestamps and empty or inverted intervals;
- replayed identifiers, forged references, non-increasing per-stream sequences, decreasing record times, and broken hash ancestry;
- conflict decisions made against stale state;
- partial writes and destination/source aliasing during compaction;
- prompt injection, untrusted model output, credential leakage, unbounded responses, and unexpected network destinations in the optional adapter;
- accidental inclusion of sensitive runtime data or real user content in fixtures and diagnostics.

The implementation plan turns these threats into negative tests and bounded failure behavior.

## Secrets and model adapters

The offline fixture path is the default. The native OpenAI-compatible adapter must be disabled unless explicitly configured, read credentials from the process environment, restrict endpoints to an operator-supplied allowlist, apply connection and response-size limits, and redact authorization material from errors. Credentials must never be written into facts, journal records, snapshots, fixtures, logs, or test output.

An OpenAI-compatible response is untrusted input. It must pass the same parser, schema validation, temporal validation, provenance requirements, and conflict guard as offline input. Model output never receives authority to rewrite history or resolve a conflict silently.

## Dependency and release hygiene

- Pin dependencies and review their source, maintenance state, supported targets, license, and advisories before adoption.
- Keep third-party notices synchronized with dependency changes.
- Verify committed `pkg.generated.mbti` changes and deterministic golden artifacts during review.
- Build releases from a clean checkout and retain the expected journal head hashes for distributed fixtures.
- Never claim tamper evidence when the expected chain head is obtained only from the untrusted artifact being checked.
