# ADR 0003: Keep fact closure explicit and terminal

- Status: accepted
- Date: 2026-09-05

## Context

A replacement changes what is visible, but it must not rewrite what a source originally asserted. Deriving closure from a currently preferred candidate would also make replay depend on an implicit conflict policy and could reproduce the cross-fact invalidation class documented by Graphiti issue 1728.

## Decision

`FactAssertion` remains immutable. Each `FactId` may acquire exactly one terminal `FactClosure`, created only by `SupersedeFact` or `RetractFact`. A supersession carries its candidate, a sorted non-empty old-fact set, and an immutable `ConflictDecision`; a retraction carries its target, explicit effective time, and non-empty reason. A second different closure is rejected, while exact envelope replay remains idempotent.

The effective exclusive valid-time end is the earlier of the assertion's original end and the closure's effective time. A cutoff at or before `valid_from` produces an empty derived interval without constructing an invalid `ValidInterval`. A cutoff after an assertion end remains auditable but does not change that assertion-defined end.

Supersession validates every old fact before publishing any change. Old and candidate facts must share group, subject, ASCII predicate key, object kind, and strictly overlapping valid intervals. Entity references additionally preserve the directed object endpoint; literal values may change. These guards are an independently implemented `documented_adaptation`, not an upstream translation.

## Consequences

- Historical assertions and their provenance remain inspectable.
- Known-time prefix replay naturally excludes future closures.
- Query and diff use the derived interval; history includes activation or closure changes; explanation reports both the visibility reason and bounded lifecycle chain.
- One terminal closure makes lifecycle validation simple and auditable. Reopening a fact requires a new `FactId`, not mutation of the old assertion.
