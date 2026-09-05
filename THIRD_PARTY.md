# Third-party notices

## Graphiti

- Project: [Graphiti](https://github.com/getzep/graphiti)
- Reference version: `0.30.1`
- Reference commit: `547422865cca9fb5a82915c074d899428c145ff4`
- Upstream license: Apache License 2.0
- Upstream copyright notice used by this project: `Copyright 2024, Zep Software, Inc.`

`graphiti_normalize.mbt`, `graphiti_candidate_dedup.mbt`, `graphiti_retrieval.mbt`, and the development-only Python oracles translate, modify, or directly reproduce the pinned pre-ID entity-edge normalization/deduplication and search-helper behavior. Graphiti is not a runtime dependency. FactEpoch's episode-reference union, literal pass-through, explicit group isolation, conflict structural guards, retrieval validation, canonical RRF accumulation, and stable ID tie breaking are recorded as `documented_adaptation`.

Every future file that is translated from or structurally derived from Graphiti source must include this leading notice in the appropriate comment syntax:

```text
SPDX-License-Identifier: Apache-2.0
Portions derived from getzep/graphiti.
Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
Copyright 2024, Zep Software, Inc.
Translated and modified for MoonBit in 2026.
```

Development-only Python oracles use the same attribution with a final line describing the file as an adapted fixture oracle rather than MoonBit production code.

The same change must add the upstream path and destination path to [docs/upstream.md](docs/upstream.md). Compatibility fixtures must identify the upstream symbol and use `exact_upstream` or `documented_adaptation` honestly.

Names and trademarks belong to their owners. Reference to Graphiti does not imply affiliation or endorsement.

## Unicode Character Database

- Data profile: Unicode Character Database `15.0.0`
- Retrieved: 2026-09-05
- License source: [unicode.org/license.txt](https://www.unicode.org/license.txt)
- Copyright: `Copyright © 1991-2026 Unicode, Inc.`
- License: Unicode License V3; full text at [`third_party/unicode/LICENSE.txt`](third_party/unicode/LICENSE.txt)
- Generated destination: `graphiti_unicode_tables.generated.mbt`

The generated table reproduces the lowercase, contextual-property, and 29-whitespace-scalar behavior of the pinned CPython oracle profile. Its header carries `SPDX-FileCopyrightText` and `Unicode-3.0`. The project does not distribute CPython source or binaries. Generated production rows and generated fixture tests are kept separate from handwritten MoonBit and reported as separate LOC categories.

## MoonBit dependencies

The implementation plans to use `moonbitlang/x@0.5.1` for pure-MoonBit SHA-256 and `moonbitlang/async@0.21.2` for native asynchronous boundaries. They are not dependencies until they appear in `moon.mod`. Their licenses and required notices will be recorded here in the same change that adds them.

Every later dependency must be reproducibly versioned and reviewed for license, target support, maintenance, and redistribution obligations.
