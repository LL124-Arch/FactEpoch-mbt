# Contributing to FactEpoch-mbt

FactEpoch-mbt is in the design-to-implementation stage. Contributions must preserve the bitemporal, deterministic, append-only, and pure-MoonBit core described in the [design contract](docs/design.md).

## Before changing code

1. Read the design contract, [implementation plan](docs/implementation-plan.md), `SECURITY.md`, and the relevant decision records.
2. Confirm that the change is inside the documented scope. A server, UI, vector store, silent conflict resolution, distributed writer coordination, or destructive history mutation belongs outside this repository.
3. Search the current packages with `moon ide outline` and inspect APIs with `moon ide doc` or `moon ide peek-def` before introducing names.
4. Keep all public domain types and `MemoryGraph` in the root `moon.pkg` and root `*.mbt` files. Put encoding, integrity, compaction, extraction, CLI, examples, compatibility tooling, fixtures, and benchmarks in the named supporting packages documented in `README.md` and `docs/architecture.md`.

## Test-driven workflow

Every behavior change follows red-green-refactor:

1. Add the smallest failing black-box test that expresses the public behavior. Use white-box tests only for an invariant that cannot be observed safely through the public boundary.
2. Run the narrowest test command and record the expected failure reason. A compilation failure is acceptable only when it demonstrates the missing API under test.
3. Add the minimum implementation that makes the new test pass.
4. Run the targeted test again, then the relevant package suite.
5. Refactor without changing behavior and rerun the suite.
6. Run repository-wide validation before committing.

Tests involving extraction use committed synthetic fixtures. They must not depend on live model output, current time, random iteration order, external databases, or network access. Golden JSONL and hash values must be reviewed as protocol artifacts, not updated blindly.

## Required local checks

Once `moon.mod` exists, run from the module root:

```powershell
moon check --target all --warn-list +73
moon test --target all
moon check --target native --warn-list +73
moon test --target native
moon fmt
moon check --fmt
moon info --target all
git diff --check
git status --short
```

Review every changed `pkg.generated.mbti`. Public API changes require a design rationale, migration note, and changelog entry.

## Change structure

- Keep a commit centered on one independently testable capability, including its tests and documentation.
- Describe the actual reason for a change in the subject and keep the body useful to a reviewer.
- Do not manufacture history, backdate commits, create empty commits, or split a coherent change merely to increase the commit count.
- Let boundaries follow real development: exploratory fixes and follow-up corrections are acceptable, while repetitive quota-shaped commits are not.
- Do not combine formatting churn, unrelated refactors, generated run data, or dependency changes with a behavioral change.
- Add a changelog entry for user-visible behavior and update `THIRD_PARTY.md` when a dependency or adapted source introduces attribution obligations.

## Data, provenance, and security

- Fixtures must be synthetic or cleared for public redistribution.
- Never commit API keys, authorization headers, private prompts, raw production facts, model transcripts, or generated journals containing sensitive data.
- Every accepted assertion must preserve source provenance; extraction confidence never replaces provenance.
- Conflict resolution must be explicit and auditable. A model suggestion cannot bypass the conflict guard.
- Follow `SECURITY.md` for suspected vulnerabilities or leaked credentials.

By submitting a contribution, you agree that it is licensed under Apache License 2.0 and that you have the right to submit it under those terms.
