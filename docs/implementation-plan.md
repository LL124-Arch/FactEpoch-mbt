# Implementation Plan

This plan organizes work around user-visible outcomes and verification checkpoints. It does not require one commit per checklist item or prescribe commit wording. Changes should be committed when they form a coherent, reviewable capability with its tests and documentation.

## Working rules

- Use test-driven development: observe the intended test fail, add the smallest implementation, then refactor with the suite green.
- Keep the portable root independent of clock, files, environment, database, and network.
- Treat golden protocol files and generated interfaces as reviewed source artifacts.
- Do not manufacture activity through empty commits, quota-sized splitting, backdating, or post-hoc history rewriting.
- Preserve a natural history: a capability may take several commits when real corrections occur, while tightly coupled changes may share one commit.

## Foundation checkpoint

Outcome: a valid `LL124-Arch/factepoch` module with Apache-2.0 metadata and a root public package.

- Add current `moon.mod` and root `moon.pkg` formats.
- Introduce opaque IDs and UTC Unix-millisecond `Timestamp` with half-open interval tests.
- Define the domain records, provenance validation, errors, and generated public interface.
- Check all four core targets and document any target-specific exclusion.

Evidence: targeted tests, `moon check --target all`, `moon test --target all`, formatting check, and reviewed `pkg.generated.mbti`.

## Event and temporal checkpoint

Outcome: events can be applied atomically and queried along valid and known time.

- Add failing tests for batch rollback, idempotent event replay, and same-ID/different-payload rejection.
- Implement episode/entity/fact events and deterministic replay.
- Add current, historical, late-arrival, boundary, history, and diff tests.
- Implement explicit supersession, retraction, group isolation, and provenance explanations.
- Lock Graphiti pre-ID entity-reference candidate-dedup fixtures and the issue-1728 structural adaptation.

Evidence: the complete bitemporal matrix passes on all core targets and repeated replay produces the same semantic digest.

## Search checkpoint

Outcome: deterministic local retrieval composes with external ranked candidates.

- Test filtered queries, bounded BFS, direction handling, cosine failures, and RRF ties.
- Implement the ranked-candidate DTO without freezing an async embedder interface.
- Prove stable score/time/ID ordering independent of insertion and map iteration order.

Evidence: permutation tests return byte-identical result sequences.

## Journal and integrity checkpoint

Outcome: a versioned JSONL stream round-trips and detects corruption.

- Write negative tests for unknown schema, duplicate keys, noncanonical encoding, CRLF, non-increasing sequences, decreasing record times, broken ancestry, invalid event hashes, damaged lines, and truncated tails.
- Implement the manual v1 field order and canonical UTF-8/LF encoding.
- Integrate `moonbitlang/x@0.5.1` SHA-256 and verify NIST/Python vectors, Chinese text, and emoji.
- Add event-chain, state, redaction-set, and artifact digests.

Evidence: encode/decode/replay equivalence and cross-target golden bytes.

## Forget and compact checkpoint

Outcome: forgetting is explicit, reproducible, and does not endanger the source artifact.

- Test selector resolution, frozen affected IDs, stale-plan rejection, and zero partial writes.
- Implement logical `ApplyForgetPlan` without dynamic cascading.
- Test preserve equivalence across all observable history.
- Test that redact output lacks forgotten bodies, retains markers, and preserves the unforgotten projection.
- Implement native sibling-temp publication, sync/read-back verification, immutable generations, and receipts.
- Inject publication failures and prove the input is byte-identical afterward.

Evidence: receipts match source/output digests and no compaction path overwrites or deletes its input.

## Compatibility, CLI, and examples checkpoint

Outcome: users can exercise the kernel offline and inspect Graphiti parity.

- Pin Python oracle metadata to the upstream commit; generate `exact_upstream` and `documented_adaptation` fixtures.
- Implement the specified `factepoch` command tree with stable exit behavior.
- Complete `profile_drift`, `repo_decisions`, and `support_case` as offline end-to-end tests.
- Check the executable and file-publication behavior on Ubuntu, Windows, and macOS.

Evidence: every example runs from a clean clone and fixture drift checks are reproducible without Python at runtime.

## Extraction checkpoint

Outcome: deterministic extraction remains the default and live extraction cannot mutate memory directly.

- Implement async `extract/api` and the fixture extractor.
- Add the native-only OpenAI-compatible adapter using `moonbitlang/async@0.21.2`.
- Test timeout, HTTP errors, malformed responses, size limits, strict candidate validation, token redaction, and zero graph writes.
- Use an injected transport or fake local service; CI never contacts a real provider.

Evidence: core target checks do not import the adapter, and every adapter failure returns candidates or an error without state mutation.

## Release-readiness checkpoint

Outcome: a clean clone supplies reproducible evidence for `v0.1.0`.

- Benchmark 10,000 events and report replay throughput, query latency, and artifact size without inventing performance or LOC thresholds.
- Finish English and Chinese documentation, source mapping, limitations, changelog, CI, and security review.
- Run Ubuntu `moon check --target all`, `moon test --target all`, `moon check --fmt`, `moon info --target all`, native build, README/quickstart checks, Python fixture drift, and `moon publish --dry-run`.
- Run native CLI and failure-injection tests on Ubuntu, Windows, and macOS.
- From a clean clone, create `docs/release-audit.md` recording public repository visibility, remote URL, default branch/remote HEAD, license and attribution, commit authorship, file/line counts by production/test/example category excluding generated files, CI, examples, dry-run publication, Mooncakes page, and installation smoke test.
- Correct every failed audit item and rerun the full audit before tagging `v0.1.0`, creating a GitHub Release, or publishing to Mooncakes.

The competition application is an external readiness checkpoint: at submission time the repository must have at least ten meaningful commits if that remains the official requirement. This is verified, not manufactured. Proposal wording, personal information, community enrollment, and form submission remain the participant's work.
