# ADR 0002: Project facts across valid and known time

- Status: accepted
- Date: 2026-09-05

## Context

The ingestion milestone retained each assertion's valid interval and its first activation envelope, but callers could not yet ask what was valid at one world-time point using only information recorded by another system-time point. The read API also needed a stable predicate key without rewriting the predicate supplied by a source.

We considered filtering the current graph's retained activation fields directly. That is sufficient for today's assertion-only lifecycle, but it makes the read path depend on whatever future state happens to be materialized and creates a separate semantics path from normal ingestion. A later closure or forget implementation could then leak knowledge from after the requested boundary. We also rejected using a mutable `valid_to` field for closures because it would erase the assertion originally supplied by the caller.

## Decision

`MemoryGraph::query` takes the event prefix whose envelopes have `recorded_at <= known_at`, rebuilds a temporary graph through the ordinary `MemoryGraph::replay` validation path, and only then filters assertions whose interval contains `valid_at`. Stream `recorded_at` is monotonic, so prefix collection stops at the first future event. The comparison is inclusive on known time, so all events recorded in the same millisecond are replayed; `seq` orders them but does not make only a prefix of that millisecond queryable. Valid intervals remain half-open: `[valid_from, valid_to)`.

The current result score is `confidence_basis_points: Int` and results sort by descending score, descending `valid_from`, then ascending `FactId`. This is deliberately not the future ranked-candidate `Double` score.

Predicate structure and filters use one private normalization profile:

1. map ASCII `A` through `Z` to `a` through `z`;
2. treat bytes `0x09` through `0x0D` and `0x20` as whitespace, collapse each run to one ASCII space, and trim leading/trailing runs;
3. preserve every other Unicode scalar, underscore, and hyphen exactly;
4. perform no Unicode normalization.

The raw predicate stays in `FactAssertion`. A predicate whose normalized key is empty is rejected. `FactView::predicate_key` and `FactSlot::predicate_key` expose the derived key without exposing the helper.

`history` first replays through its inclusive `to_known_at`, then reports first activations in the closed knowledge-time window, targeted by exact `FactId` or by group, subject, and normalized predicate slot. Closure markers will join this result only when closure events exist. A knowledge-axis `diff` replays independently at both known-time endpoints. A valid-axis `diff` replays once at its fixed known time, then filters the two valid-time points. Added and unchanged views come from the right projection; removed views come from the left.

Future closure events will not mutate a stored assertion:

- `SupersedeFact` derives the old fact's effective exclusive `valid_to` as the earlier of its original `valid_to` and the new fact's `valid_from`.
- `RetractFact` carries an explicit `effective_at` and derives the old fact's effective exclusive `valid_to` as the earlier of its original `valid_to` and `effective_at`.
- Each closure affects known-time projection only once its own envelope has `recorded_at <= known_at`.
- An applied forget plan hides affected material from normal queries while history and explanation retain redaction-aware audit markers.

These future rules are frozen semantics, not claims that supersession, retraction, forgetting, or closure-aware history are implemented in this milestone.

## Consequences

- Late assertions can change today's understanding of an older valid-time point without appearing in earlier known-time queries.
- Read results do not depend on map iteration or assertion insertion order.
- Result arrays and diff partitions are defensive; callers cannot mutate graph state through them.
- Every known-time read pays for prefix collection and normal replay. Prefix traversal stops at the first future envelope, and replay rebuilds indexed state with expected linear work rather than adding a second materialization path.
- Immutable assertions and reserved closure metadata leave a direct path to explicit conflict events without changing the query mechanism.
- Canonically equivalent Unicode spellings can remain distinct predicate keys. Callers that need Unicode normalization must perform and document it before constructing assertions.
