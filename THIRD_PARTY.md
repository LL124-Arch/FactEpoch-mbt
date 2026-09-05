# Third-party notices

## Graphiti

- Project: [Graphiti](https://github.com/getzep/graphiti)
- Reference version: `0.30.1`
- Reference commit: `547422865cca9fb5a82915c074d899428c145ff4`
- Upstream license: Apache License 2.0
- Upstream copyright notice used by this project: `Copyright 2024, Zep Software, Inc.`

The current implementation contains no copied, vendored, or translated Graphiti source and has no Graphiti runtime dependency. Its independently written conflict and structural-guard behavior is recorded as a `documented_adaptation`; selected deterministic pre-ID candidate deduplication and ranking behavior remains planned for later migration.

Every future file that is translated from or structurally derived from Graphiti source must include this leading notice in the appropriate comment syntax:

```text
SPDX-License-Identifier: Apache-2.0
Portions derived from getzep/graphiti.
Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
Copyright 2024, Zep Software, Inc.
Translated and modified for MoonBit in 2026.
```

The same change must add the upstream path and destination path to [docs/upstream.md](docs/upstream.md). Compatibility fixtures must identify the upstream symbol and use `exact_upstream` or `documented_adaptation` honestly.

Names and trademarks belong to their owners. Reference to Graphiti does not imply affiliation or endorsement.

## MoonBit dependencies

The implementation plans to use `moonbitlang/x@0.5.1` for pure-MoonBit SHA-256 and `moonbitlang/async@0.21.2` for native asynchronous boundaries. They are not dependencies until they appear in `moon.mod`. Their licenses and required notices will be recorded here in the same change that adds them.

Every later dependency must be reproducibly versioned and reviewed for license, target support, maintenance, and redistribution obligations.
