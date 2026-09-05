#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Portions derived from getzep/graphiti.
# Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
# Copyright 2024, Zep Software, Inc.
# Adapted as a fixture oracle for FactEpoch-mbt in 2026.
"""Validate pinned Graphiti search fixtures and render MoonBit tests."""

from __future__ import annotations

import argparse
import json
import math
import struct
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "fixtures" / "graphiti"
GENERATED = ROOT / "graphiti_search_fixture.generated_wbtest.mbt"
PIN = "547422865cca9fb5a82915c074d899428c145ff4"
SCHEMA = "factepoch.graphiti-search/v1"
UPSTREAM = {
    "repository": "https://github.com/getzep/graphiti",
    "version": "0.30.1",
    "commit": PIN,
    "source": "graphiti_core/search/search_utils.py",
    "symbols": ["calculate_cosine_similarity", "rrf"],
}


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def exact_keys(value: Any, keys: set[str], where: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        actual = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise SystemExit(f"{where}: expected keys {sorted(keys)}, got {actual}")
    return value


def finite_number(value: Any, where: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise SystemExit(f"{where}: expected a finite number")
    return float(value)


def nonempty_string(value: Any, where: str) -> str:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{where}: expected a non-empty string")
    return value


def load(name: str) -> dict[str, Any]:
    path = FIXTURES / name
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"invalid fixture {path}: {error}") from error
    return value


def validate_common(value: Any, parity: str, keys: set[str], where: str) -> dict[str, Any]:
    root = exact_keys(value, {"fixture_schema", "parity_kind", "upstream"} | keys, where)
    if root["fixture_schema"] != SCHEMA or root["parity_kind"] != parity:
        raise SystemExit(f"{where}: schema or parity label drifted")
    if root["upstream"] != UPSTREAM:
        raise SystemExit(f"{where}: pinned upstream metadata drifted")
    return root


def graphiti_cosine(left: list[float], right: list[float]) -> float:
    if len(left) != len(right):
        raise ValueError("dimension mismatch")
    dot = sum(a * b for a, b in zip(left, right, strict=True))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0
    return dot / (left_norm * right_norm)


def graphiti_rrf(
    results: list[list[str]], rank_constant: int, minimum_score: float
) -> tuple[list[str], list[float]]:
    scores: defaultdict[str, float] = defaultdict(float)
    first_seen: dict[str, int] = {}
    for result in results:
        for rank, fact_id in enumerate(result):
            first_seen.setdefault(fact_id, len(first_seen))
            scores[fact_id] += 1 / (rank + rank_constant)
    ordered = sorted(scores, key=lambda fact_id: (-scores[fact_id], first_seen[fact_id]))
    kept = [fact_id for fact_id in ordered if scores[fact_id] >= minimum_score]
    return kept, [scores[fact_id] for fact_id in kept]


def validate_exact(value: Any) -> dict[str, Any]:
    root = validate_common(value, "exact_upstream", {"cosine_cases", "rrf_cases"}, "exact")
    names: list[str] = []
    for index, case_value in enumerate(root["cosine_cases"]):
        where = f"exact.cosine_cases[{index}]"
        case = exact_keys(case_value, {"name", "left", "right", "expected"}, where)
        names.append(nonempty_string(case["name"], f"{where}.name"))
        if not isinstance(case["left"], list) or not isinstance(case["right"], list):
            raise SystemExit(f"{where}: vectors must be arrays")
        left = [finite_number(item, f"{where}.left") for item in case["left"]]
        right = [finite_number(item, f"{where}.right") for item in case["right"]]
        expected = finite_number(case["expected"], f"{where}.expected")
        if not math.isclose(graphiti_cosine(left, right), expected, abs_tol=1e-12):
            raise SystemExit(f"{where}: expected value disagrees with pinned formula")
    for index, case_value in enumerate(root["rrf_cases"]):
        where = f"exact.rrf_cases[{index}]"
        case = exact_keys(
            case_value,
            {"name", "rank_constant", "minimum_score", "lists", "expected_ids", "expected_scores"},
            where,
        )
        names.append(nonempty_string(case["name"], f"{where}.name"))
        rank_constant = case["rank_constant"]
        if isinstance(rank_constant, bool) or not isinstance(rank_constant, int) or rank_constant <= 0:
            raise SystemExit(f"{where}.rank_constant: expected positive integer")
        minimum_score = finite_number(case["minimum_score"], f"{where}.minimum_score")
        if not isinstance(case["lists"], list) or not all(isinstance(row, list) for row in case["lists"]):
            raise SystemExit(f"{where}.lists: expected arrays")
        lists = [[nonempty_string(item, f"{where}.lists") for item in row] for row in case["lists"]]
        if not isinstance(case["expected_ids"], list) or not isinstance(case["expected_scores"], list):
            raise SystemExit(f"{where}: expected arrays")
        expected_ids = [nonempty_string(item, f"{where}.expected_ids") for item in case["expected_ids"]]
        expected_scores = [finite_number(item, f"{where}.expected_scores") for item in case["expected_scores"]]
        ids, scores = graphiti_rrf(lists, rank_constant, minimum_score)
        if ids != expected_ids or scores != expected_scores:
            raise SystemExit(f"{where}: expected result disagrees with pinned formula")
    if len(names) != len(set(names)):
        raise SystemExit("exact fixture names must be unique")
    return root


def validate_candidate(value: Any, where: str) -> dict[str, Any]:
    candidate = exact_keys(value, {"fact_id", "zero_based_rank", "source_score"}, where)
    nonempty_string(candidate["fact_id"], f"{where}.fact_id")
    rank = candidate["zero_based_rank"]
    if isinstance(rank, bool) or not isinstance(rank, int) or rank < 0:
        raise SystemExit(f"{where}.zero_based_rank: expected non-negative integer")
    if candidate["source_score"] is not None:
        finite_number(candidate["source_score"], f"{where}.source_score")
    return candidate


def validate_lists(value: Any, where: str) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise SystemExit(f"{where}: expected an array")
    lists: list[dict[str, Any]] = []
    for list_index, list_value in enumerate(value):
        list_where = f"{where}[{list_index}]"
        ranked = exact_keys(list_value, {"source", "candidates"}, list_where)
        nonempty_string(ranked["source"], f"{list_where}.source")
        if not isinstance(ranked["candidates"], list):
            raise SystemExit(f"{list_where}.candidates: expected an array")
        candidates = [
            validate_candidate(item, f"{list_where}.candidates[{index}]")
            for index, item in enumerate(ranked["candidates"])
        ]
        ranks = sorted(candidate["zero_based_rank"] for candidate in candidates)
        if ranks != list(range(len(candidates))):
            raise SystemExit(f"{list_where}: fixture ranking must be complete")
        if len({candidate["fact_id"] for candidate in candidates}) != len(candidates):
            raise SystemExit(f"{list_where}: fixture FactIds must be unique")
        lists.append(ranked)
    sources = [ranked["source"] for ranked in lists]
    if len(sources) != len(set(sources)):
        raise SystemExit(f"{where}: fixture sources must be unique")
    return lists


def ranking_signature(lists: list[dict[str, Any]]) -> list[tuple[str, list[tuple[str, int, float | None]]]]:
    return sorted(
        (
            ranked["source"],
            sorted(
                (
                    candidate["fact_id"],
                    candidate["zero_based_rank"],
                    candidate["source_score"],
                )
                for candidate in ranked["candidates"]
            ),
        )
        for ranked in lists
    )


def factepoch_rrf(lists: list[dict[str, Any]], rank_constant: int, minimum_score: float) -> list[dict[str, Any]]:
    fused: dict[str, dict[str, Any]] = {}
    for ranked in sorted(lists, key=lambda item: item["source"]):
        for candidate in sorted(ranked["candidates"], key=lambda item: item["zero_based_rank"]):
            contribution = 1.0 / (candidate["zero_based_rank"] + rank_constant)
            current = fused.setdefault(
                candidate["fact_id"],
                {"fact_id": candidate["fact_id"], "score": 0.0, "contributions": []},
            )
            current["score"] += contribution
            current["contributions"].append(
                {
                    "source": ranked["source"],
                    "zero_based_rank": candidate["zero_based_rank"],
                    "contribution": contribution,
                }
            )
    return sorted(
        (item for item in fused.values() if item["score"] >= minimum_score),
        key=lambda item: (-item["score"], item["fact_id"]),
    )


def raw_order_score_bits(lists: list[dict[str, Any]], fact_id: str, rank_constant: int) -> int:
    score = 0.0
    for ranked in lists:
        for candidate in ranked["candidates"]:
            if candidate["fact_id"] == fact_id:
                score += 1.0 / (candidate["zero_based_rank"] + rank_constant)
    return struct.unpack(">Q", struct.pack(">d", score))[0]


def validate_expected_fused(value: Any, where: str) -> list[dict[str, Any]]:
    expected = exact_keys(value, {"fused"}, where)
    if not isinstance(expected["fused"], list):
        raise SystemExit(f"{where}.fused: expected an array")
    output: list[dict[str, Any]] = []
    for item_index, item_value in enumerate(expected["fused"]):
        item_where = f"{where}.fused[{item_index}]"
        item = exact_keys(item_value, {"fact_id", "score", "contributions"}, item_where)
        nonempty_string(item["fact_id"], f"{item_where}.fact_id")
        finite_number(item["score"], f"{item_where}.score")
        if not isinstance(item["contributions"], list) or not item["contributions"]:
            raise SystemExit(f"{item_where}.contributions: expected non-empty array")
        for contribution_index, contribution_value in enumerate(item["contributions"]):
            contribution_where = f"{item_where}.contributions[{contribution_index}]"
            contribution = exact_keys(
                contribution_value,
                {"source", "zero_based_rank", "contribution"},
                contribution_where,
            )
            nonempty_string(contribution["source"], f"{contribution_where}.source")
            rank = contribution["zero_based_rank"]
            if isinstance(rank, bool) or not isinstance(rank, int) or rank < 0:
                raise SystemExit(f"{contribution_where}.zero_based_rank: invalid")
            finite_number(contribution["contribution"], f"{contribution_where}.contribution")
        output.append(item)
    return output


def validate_adaptation(value: Any) -> dict[str, Any]:
    root = validate_common(value, "documented_adaptation", {"cases"}, "adaptation")
    expected_operations = {
        "fact-id-tie-break": "rrf",
        "canonical-source-permutation": "rrf_permutation",
        "reject-ambiguous-ranking": "rank_validation",
        "reject-nonfinite-values": "finite_validation",
    }
    seen: set[str] = set()
    for index, case_value in enumerate(root["cases"]):
        where = f"adaptation.cases[{index}]"
        case = exact_keys(case_value, {"name", "reason", "operation", "input", "expected"}, where)
        name = nonempty_string(case["name"], f"{where}.name")
        nonempty_string(case["reason"], f"{where}.reason")
        if name in seen or expected_operations.get(name) != case["operation"]:
            raise SystemExit(f"{where}: unexpected name, duplicate, or operation")
        seen.add(name)
        operation = case["operation"]
        if operation in {"rrf", "rrf_permutation"}:
            input_keys = {"rank_constant", "minimum_score", "lists" if operation == "rrf" else "permutations"}
            input_value = exact_keys(case["input"], input_keys, f"{where}.input")
            rank_constant = input_value["rank_constant"]
            if isinstance(rank_constant, bool) or not isinstance(rank_constant, int) or rank_constant <= 0:
                raise SystemExit(f"{where}.rank_constant: expected positive integer")
            minimum_score = finite_number(input_value["minimum_score"], f"{where}.minimum_score")
            permutations = (
                [validate_lists(input_value["lists"], f"{where}.input.lists")]
                if operation == "rrf"
                else [
                    validate_lists(permutation, f"{where}.input.permutations[{position}]")
                    for position, permutation in enumerate(input_value["permutations"])
                ]
            )
            if operation == "rrf_permutation":
                if len(permutations) < 2 or any(len(permutation) < 3 for permutation in permutations):
                    raise SystemExit(f"{where}: permutation fixture needs two permutations and three sources")
                signature = ranking_signature(permutations[0])
                if any(ranking_signature(permutation) != signature for permutation in permutations[1:]):
                    raise SystemExit(f"{where}: permutations may change order only")
                target_ranks = {
                    candidate["zero_based_rank"]
                    for ranked in permutations[0]
                    for candidate in ranked["candidates"]
                    if candidate["fact_id"] == "a"
                }
                if target_ranks != {0, 1, 5}:
                    raise SystemExit(f"{where}: permutation fixture must exercise ranks 0, 1, and 5")
                raw_bits = {
                    raw_order_score_bits(permutation, "a", rank_constant)
                    for permutation in permutations
                }
                if len(raw_bits) < 2:
                    raise SystemExit(
                        f"{where}: raw source-order accumulation must produce at least two UInt64 bit patterns"
                    )
            expected = validate_expected_fused(case["expected"], f"{where}.expected")
            for permutation in permutations:
                actual = factepoch_rrf(permutation, rank_constant, minimum_score)
                if actual != expected:
                    raise SystemExit(f"{where}: expected fused result disagrees with adaptation")
        else:
            input_value = exact_keys(case["input"], {"checks"}, f"{where}.input")
            expected = exact_keys(case["expected"], {"all_rejected"}, f"{where}.expected")
            if expected["all_rejected"] is not True or not isinstance(input_value["checks"], list):
                raise SystemExit(f"{where}: validation fixture must expect all checks rejected")
            expected_checks = {
                "rank_validation": {
                    "blank_source": "InvalidRankSource",
                    "duplicate_fact_id": "DuplicateRankedCandidate",
                    "duplicate_rank": "DuplicateCandidateRank",
                    "rank_gap": "InvalidCandidateRank",
                    "duplicate_source": "DuplicateRankSource",
                },
                "finite_validation": {
                    "left_nan": "NonFiniteVectorValue",
                    "source_score_infinity": "NonFiniteRankedScore",
                    "minimum_score_nan": "InvalidMinimumScore",
                    "cosine_overflow": "NonFiniteVectorComputation",
                },
            }[operation]
            checks: dict[str, str] = {}
            for check_index, check_value in enumerate(input_value["checks"]):
                check = exact_keys(
                    check_value,
                    {"kind", "expected_error"},
                    f"{where}.input.checks[{check_index}]",
                )
                if check["kind"] in checks:
                    raise SystemExit(f"{where}: duplicate executable validation check")
                checks[check["kind"]] = check["expected_error"]
            if checks != expected_checks:
                raise SystemExit(f"{where}: executable validation checks drifted")
    if seen != set(expected_operations):
        raise SystemExit("adaptation fixture case set drifted")
    return root


def mbt_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def mbt_double(value: float | int) -> str:
    number = float(value)
    text = repr(number)
    return text if "." in text or "e" in text.lower() else text + ".0"


def render_ranked_lists(lists: list[dict[str, Any]], indent: str) -> list[str]:
    lines = [indent + "["]
    for ranked in lists:
        lines.append(indent + f"  generated_ranked_list({mbt_string(ranked['source'])}, [")
        for candidate in ranked["candidates"]:
            source_score = (
                "None"
                if candidate["source_score"] is None
                else f"Some({mbt_double(candidate['source_score'])})"
            )
            lines.append(
                indent
                + f"    generated_ranked_candidate({mbt_string(candidate['fact_id'])}, "
                + f"{candidate['zero_based_rank']}, {source_score}),"
            )
        lines.append(indent + "  ]),")
    lines.append(indent + "],")
    return lines


def render_fused_assertions(variable: str, expected: list[dict[str, Any]]) -> list[str]:
    lines = [
        "  inspect(",
        f"    {variable}.map(value => value.fact_id().value()).join(\",\"),",
        f"    content={mbt_string(','.join(item['fact_id'] for item in expected))},",
        "  )",
    ]
    for item_index, item in enumerate(expected):
        lines.extend(
            [
                "  inspect(",
                f"    {variable}[{item_index}].score().reinterpret_as_uint64() ==",
                f"    {mbt_double(item['score'])}.reinterpret_as_uint64(),",
                '    content="true",',
                "  )",
                f"  let contributions_{variable}_{item_index} = {variable}[{item_index}].contributions()",
                f"  inspect(contributions_{variable}_{item_index}.length(), content={mbt_string(str(len(item['contributions'])))})",
            ]
        )
        for contribution_index, contribution in enumerate(item["contributions"]):
            reference = f"contributions_{variable}_{item_index}[{contribution_index}]"
            lines.extend(
                [
                    f"  inspect({reference}.source(), content={mbt_string(contribution['source'])})",
                    f"  inspect({reference}.zero_based_rank(), content={mbt_string(str(contribution['zero_based_rank']))})",
                    "  inspect(",
                    f"    {reference}.contribution().reinterpret_as_uint64() ==",
                    f"    {mbt_double(contribution['contribution'])}.reinterpret_as_uint64(),",
                    '    content="true",',
                    "  )",
                ]
            )
    return lines


def render_tests(exact: dict[str, Any], adaptation: dict[str, Any]) -> str:
    lines = [
        "// SPDX-License-Identifier: Apache-2.0",
        "// @generated by compat/python/oracle_graphiti_search_v0301.py; DO NOT EDIT.",
        "// Generated fixture tests are excluded from handwritten-test LOC.",
        "// Graphiti's first-seen tie is Python-oracle evidence only; FactEpoch",
        "// exercises its documented FactId tie adaptation below.",
        "",
        "///|",
        "fn generated_ranked_candidate(",
        "  id : String,",
        "  rank : Int,",
        "  score : Double?,",
        ") -> RankedCandidate raise MemoryError {",
        "  RankedCandidate::new(FactId::new(id), rank, score)",
        "}",
        "",
        "///|",
        "fn generated_ranked_list(",
        "  source : String,",
        "  candidates : Array[RankedCandidate],",
        ") -> RankedCandidateList raise MemoryError {",
        "  RankedCandidateList::new(source, candidates)",
        "}",
    ]
    for case in exact["cosine_cases"]:
        lines.extend(
            [
                "",
                "///|",
                f"test {mbt_string('generated Graphiti exact cosine ' + case['name'])} {{",
                "  inspect(",
                f"    cosine_similarity({case['left']}, {case['right']}).is_close({mbt_double(case['expected'])}),",
                '    content="true",',
                "  )",
                "}",
            ]
        )
    for case in exact["rrf_cases"]:
        if case["name"] == "k-one-first-seen-tie":
            continue
        lists = [
            {
                "source": f"source-{index}",
                "candidates": [
                    {"fact_id": fact_id, "zero_based_rank": rank, "source_score": None}
                    for rank, fact_id in enumerate(row)
                ],
            }
            for index, row in enumerate(case["lists"])
        ]
        lines.extend(
            [
                "",
                "///|",
                f"test {mbt_string('generated Graphiti exact RRF ' + case['name'])} {{",
                "  let result = reciprocal_rank_fusion(",
                *render_ranked_lists(lists, "    "),
                f"    RrfConfig::new({case['rank_constant']}, {mbt_double(case['minimum_score'])}),",
                "  )",
                "  inspect(",
                '    result.map(value => value.fact_id().value()).join(","),',
                f"    content={mbt_string(','.join(case['expected_ids']))},",
                "  )",
            ]
        )
        for index, score in enumerate(case["expected_scores"]):
            lines.extend(
                [
                    "  inspect(",
                    f"    result[{index}].score().reinterpret_as_uint64() ==",
                    f"    {mbt_double(score)}.reinterpret_as_uint64(),",
                    '    content="true",',
                    "  )",
                ]
            )
        lines.append("}")
    cases = {case["name"]: case for case in adaptation["cases"]}
    tie = cases["fact-id-tie-break"]
    lines.extend(
        [
            "",
            "///|",
            'test "generated Graphiti documented fact-id-tie-break adaptation" {',
            "  let fused = reciprocal_rank_fusion(",
            *render_ranked_lists(tie["input"]["lists"], "    "),
            f"    RrfConfig::new({tie['input']['rank_constant']}, {mbt_double(tie['input']['minimum_score'])}),",
            "  )",
            *render_fused_assertions("fused", tie["expected"]["fused"]),
            "}",
        ]
    )
    permutation = cases["canonical-source-permutation"]
    lines.extend(["", "///|", 'test "generated Graphiti documented canonical-source-permutation adaptation" {'])
    for index, lists in enumerate(permutation["input"]["permutations"]):
        lines.extend(
            [
                f"  let permutation_{index} = reciprocal_rank_fusion(",
                *render_ranked_lists(lists, "    "),
                f"    RrfConfig::new({permutation['input']['rank_constant']}, {mbt_double(permutation['input']['minimum_score'])}),",
                "  )",
                *render_fused_assertions(f"permutation_{index}", permutation["expected"]["fused"]),
            ]
        )
    lines.append("}")
    lines.extend(
        [
            "",
            "///|",
            'test "generated Graphiti documented reject-ambiguous-ranking adaptation" {',
            '  let a = FactId::new("a")',
            "  try RankedCandidateList::new(\" \", []) catch {",
            "    InvalidRankSource => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("blank source must fail")',
            "  }",
            '  try RankedCandidateList::new("duplicate-id", [',
            "    RankedCandidate::new(a, 0, None),",
            "    RankedCandidate::new(a, 1, None),",
            "]) catch {",
            "    DuplicateRankedCandidate(_) => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("duplicate ID must fail")',
            "  }",
            '  try RankedCandidateList::new("duplicate-rank", [',
            "    RankedCandidate::new(a, 0, None),",
            '    RankedCandidate::new(FactId::new("b"), 0, None),',
            "]) catch {",
            "    DuplicateCandidateRank(_) => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("duplicate rank must fail")',
            "  }",
            '  try RankedCandidateList::new("rank-gap", [',
            "    RankedCandidate::new(a, 1, None),",
            "]) catch {",
            "    InvalidCandidateRank(_, _) => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("rank gap must fail")',
            "  }",
            '  let source = RankedCandidateList::new("source", [',
            "    RankedCandidate::new(a, 0, None),",
            "])",
            "  try reciprocal_rank_fusion([source, source], RrfConfig::default()) catch {",
            "    DuplicateRankSource => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("duplicate source must fail")',
            "  }",
            "}",
            "",
            "///|",
            'test "generated Graphiti documented reject-nonfinite-values adaptation" {',
            "  try cosine_similarity([0.0 / 0.0], [1.0]) catch {",
            "    NonFiniteVectorValue(LeftVector, _) => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("NaN vector must fail")',
            "  }",
            '  try RankedCandidate::new(FactId::new("a"), 0, Some(1.0 / 0.0)) catch {',
            "    NonFiniteRankedScore(_) => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("infinite source score must fail")',
            "  }",
            "  try RrfConfig::new(1, 0.0 / 0.0) catch {",
            "    InvalidMinimumScore => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("NaN threshold must fail")',
            "  }",
            "  try cosine_similarity([1.0e308], [1.0e308]) catch {",
            "    NonFiniteVectorComputation => ()",
            '    _ => fail("unexpected error")',
            "  } noraise {",
            '    _ => fail("finite-input overflow must fail")',
            "  }",
            "}",
        ]
    )
    return "\n".join(lines) + "\n"


def format_moonbit(body: bytes) -> bytes:
    temporary = ROOT / "oracle_search_render_tmp.mbt"
    if temporary.exists():
        raise SystemExit(f"refusing to replace unexpected temporary file: {temporary}")
    try:
        temporary.write_bytes(body)
        completed = subprocess.run(
            ["moon", "fmt", str(temporary)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise SystemExit(f"MoonBit formatter rejected generated tests: {detail}")
        return temporary.read_bytes()
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="byte-compare generated MoonBit tests")
    args = parser.parse_args()
    exact = validate_exact(load("search_exact_upstream.json"))
    adaptation = validate_adaptation(load("search_documented_adaptation.json"))
    body = format_moonbit(render_tests(exact, adaptation).encode("utf-8"))
    if args.check:
        if not GENERATED.exists() or GENERATED.read_bytes() != body:
            raise SystemExit(f"generated fixture tests are stale: {GENERATED}")
        action = "checked"
    else:
        GENERATED.write_bytes(body)
        action = "wrote"
    print(f"{action}=2 search_fixtures generated_test={GENERATED.name}")


if __name__ == "__main__":
    main()
