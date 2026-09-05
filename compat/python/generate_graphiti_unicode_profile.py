#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate the pinned Graphiti normalization tables for MoonBit."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import unicodedata
from pathlib import Path

EXPECTED_PYTHON = (3, 12, 14)
EXPECTED_UCD = "15.0.0"
FINAL_SIGMA = "\N{GREEK SMALL LETTER FINAL SIGMA}"
CAPITAL_SIGMA = "\N{GREEK CAPITAL LETTER SIGMA}"
ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "graphiti_unicode_tables.generated.mbt"


def require_profile() -> None:
    implementation = sys.implementation.name
    actual_python = sys.version_info[:3]
    if implementation != "cpython" or actual_python != EXPECTED_PYTHON:
        raise SystemExit(
            f"requires CPython {EXPECTED_PYTHON}, got {implementation} {actual_python}"
        )
    if unicodedata.unidata_version != EXPECTED_UCD:
        raise SystemExit(
            f"requires Unicode {EXPECTED_UCD}, got {unicodedata.unidata_version}"
        )


def scalars():
    for codepoint in range(0x110000):
        if not 0xD800 <= codepoint <= 0xDFFF:
            yield codepoint


def as_ranges(values: list[int]) -> list[tuple[int, int]]:
    if not values:
        return []
    result: list[tuple[int, int]] = []
    start = end = values[0]
    for value in values[1:]:
        if value == end + 1:
            end = value
        else:
            result.append((start, end))
            start = end = value
    result.append((start, end))
    return result


def expand_ranges(values: list[tuple[int, int]]) -> list[int]:
    return [item for start, end in values for item in range(start, end + 1)]


def compress_lower(
    values: list[tuple[int, int]],
) -> tuple[list[tuple[int, int, int, int]], list[tuple[int, int]]]:
    runs: list[tuple[int, int, int, int]] = []
    explicit: list[tuple[int, int]] = []
    index = 0
    while index < len(values):
        best: tuple[int, int, int] | None = None
        for step in (1, 2):
            delta = values[index][1] - values[index][0]
            end = index + 1
            while (
                end < len(values)
                and values[end][0] - values[end - 1][0] == step
                and values[end][1] - values[end][0] == delta
            ):
                end += 1
            if end - index >= 2 and (best is None or end > best[0]):
                best = (end, step, delta)
        if best is None:
            explicit.append(values[index])
            index += 1
        else:
            end, step, delta = best
            runs.append((values[index][0], values[end - 1][0], step, delta))
            index = end
    return runs, explicit


def expand_lower(
    runs: list[tuple[int, int, int, int]], explicit: list[tuple[int, int]]
) -> list[tuple[int, int]]:
    expanded = list(explicit)
    for start, end, step, delta in runs:
        expanded.extend((source, source + delta) for source in range(start, end + 1, step))
    return sorted(expanded)


def tuples(name: str, width: int, values: list[tuple[int, ...]]) -> str:
    item_type = ", ".join(["Int"] * width)
    rows = ["///|", f"let {name} : FixedArray[({item_type})] = ["]
    for value in values:
        encoded = ", ".join(f"0x{x:x}" if x >= 0 else str(x) for x in value)
        rows.append(f"  ({encoded}),")
    rows.append("]")
    return "\n".join(rows)


def render() -> str:
    lower_single: list[tuple[int, int]] = []
    lower_multi: list[tuple[int, tuple[int, ...]]] = []
    whitespace: list[int] = []
    cased: list[int] = []
    case_ignorable: list[int] = []
    for codepoint in scalars():
        char = chr(codepoint)
        lowered = char.lower()
        if lowered != char:
            mapping = tuple(ord(item) for item in lowered)
            if len(mapping) == 1:
                lower_single.append((codepoint, mapping[0]))
            else:
                lower_multi.append((codepoint, mapping))
        if re.fullmatch(r"\s", char):
            whitespace.append(codepoint)
        if (" " + char + CAPITAL_SIGMA).lower().endswith(FINAL_SIGMA):
            cased.append(codepoint)
        elif ("A" + char + CAPITAL_SIGMA).lower().endswith(FINAL_SIGMA):
            case_ignorable.append(codepoint)

    expected_whitespace = [
        *range(0x0009, 0x000E),
        *range(0x001C, 0x0021),
        0x0085,
        0x00A0,
        0x1680,
        *range(0x2000, 0x200B),
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
    ]
    if lower_multi != [(0x0130, (0x0069, 0x0307))]:
        raise SystemExit(f"unexpected multi-scalar lower mappings: {lower_multi!r}")
    if whitespace != expected_whitespace:
        raise SystemExit("Python re \\s set changed")

    lower_runs, lower_explicit = compress_lower(lower_single)
    cased_ranges = as_ranges(cased)
    case_ignorable_ranges = as_ranges(case_ignorable)
    whitespace_ranges = as_ranges(whitespace)
    if len(lower_single) != 1_432 or len(lower_runs) != 88 or len(lower_explicit) != 93:
        raise SystemExit("pinned lowercase table counts changed")
    if len(cased_ranges) != 150 or len(case_ignorable_ranges) != 437:
        raise SystemExit("pinned contextual-property table counts changed")
    if len(whitespace) != 29 or len(whitespace_ranges) != 10:
        raise SystemExit("pinned whitespace table counts changed")
    if expand_lower(lower_runs, lower_explicit) != lower_single:
        raise SystemExit("compressed lowercase table does not round-trip")
    if expand_ranges(cased_ranges) != cased:
        raise SystemExit("compressed cased table does not round-trip")
    if expand_ranges(case_ignorable_ranges) != case_ignorable:
        raise SystemExit("compressed case-ignorable table does not round-trip")
    if expand_ranges(whitespace_ranges) != whitespace:
        raise SystemExit("compressed whitespace table does not round-trip")
    return "\n\n".join(
        [
            "// SPDX-License-Identifier: Unicode-3.0\n"
            "// SPDX-FileCopyrightText: 1991-2026 Unicode, Inc.\n"
            "// @generated by compat/python/generate_graphiti_unicode_profile.py; DO NOT EDIT.\n"
            "// Profile: CPython 3.12.14, UCD 15.0.0.\n"
            "// Generated tables are excluded from handwritten-source LOC.",
            tuples("graphiti_lower_runs", 4, lower_runs),
            tuples("graphiti_lower_explicit", 2, lower_explicit),
            tuples("graphiti_cased_ranges", 2, cased_ranges),
            tuples("graphiti_case_ignorable_ranges", 2, case_ignorable_ranges),
            tuples("graphiti_whitespace_ranges", 2, whitespace_ranges),
        ]
    ) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="fail unless the committed table is current"
    )
    args = parser.parse_args()
    require_profile()
    body = render()
    encoded = body.encode("utf-8")
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != encoded:
            raise SystemExit(f"generated table is stale: {OUTPUT}")
        action = "checked"
    else:
        OUTPUT.write_bytes(encoded)
        action = "wrote"
    print(
        f"{action}={OUTPUT.name} bytes={len(encoded)} "
        f"sha256={hashlib.sha256(encoded).hexdigest()}"
    )


if __name__ == "__main__":
    main()
