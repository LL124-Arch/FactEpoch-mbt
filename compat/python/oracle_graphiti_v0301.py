#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Portions derived from getzep/graphiti.
# Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
# Copyright 2024, Zep Software, Inc.
# Adapted as a fixture oracle for FactEpoch-mbt in 2026.
"""Validate Graphiti fixtures and generate their MoonBit test vectors."""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any

EXPECTED_PYTHON = (3, 12, 14)
EXPECTED_UCD = "15.0.0"
SCHEMA = "factepoch.graphiti-candidate-dedup/v1"
UPSTREAM = {
    "repository": "https://github.com/getzep/graphiti",
    "version": "0.30.1",
    "commit": "547422865cca9fb5a82915c074d899428c145ff4",
    "normalization_source": {
        "path": "graphiti_core/utils/maintenance/dedup_helpers.py",
        "symbol": "_normalize_string_exact",
    },
    "dedup_source": {
        "path": "graphiti_core/utils/maintenance/edge_operations.py",
        "symbol": "resolve_extracted_edges",
    },
}
PROFILE = {
    "implementation": "CPython",
    "version": "3.12.14",
    "ucd_version": "15.0.0",
}
ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "fixtures" / "graphiti"
GENERATED_TEST = ROOT / "graphiti_fixture_vectors.generated_wbtest.mbt"


def require_profile() -> None:
    if sys.implementation.name != "cpython" or sys.version_info[:3] != EXPECTED_PYTHON:
        raise SystemExit("oracle requires CPython 3.12.14")
    if unicodedata.unidata_version != EXPECTED_UCD:
        raise SystemExit("oracle requires UCD 15.0.0")


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_fixture(name: str) -> dict[str, Any]:
    path = FIXTURES / name
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"invalid fixture {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"{name}: root must be an object")
    return value


def exact_keys(value: Any, keys: set[str], where: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        actual = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise SystemExit(f"{where}: expected keys {sorted(keys)}, got {actual}")
    return value


def nonempty_string(value: Any, where: str) -> str:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{where}: expected a non-empty string")
    return value


def string_list(value: Any, where: str, *, nonempty: bool = True) -> list[str]:
    if not isinstance(value, list) or (nonempty and not value):
        raise SystemExit(f"{where}: expected {'a non-empty' if nonempty else 'a'} list")
    result = [nonempty_string(item, f"{where}[]") for item in value]
    return result


def unique_names(cases: list[Any], where: str) -> None:
    names = [nonempty_string(case.get("name") if isinstance(case, dict) else None, where) for case in cases]
    if len(names) != len(set(names)):
        raise SystemExit(f"{where}: case names must be unique")


def validate_common(root: dict[str, Any], expected_parity: str, where: str) -> None:
    if root["fixture_schema"] != SCHEMA:
        raise SystemExit(f"{where}: fixture_schema drifted")
    if root["parity_kind"] != expected_parity:
        raise SystemExit(f"{where}: parity_kind drifted")
    if root["upstream"] != UPSTREAM:
        raise SystemExit(f"{where}: pinned upstream metadata drifted")
    if root["runtime_profile"] != PROFILE:
        raise SystemExit(f"{where}: runtime profile drifted")


def validate_candidate(value: Any, where: str, *, entity_only: bool = False) -> dict[str, Any]:
    candidate = exact_keys(
        value,
        {
            "candidate_id",
            "group_id",
            "subject",
            "predicate",
            "object",
            "statement",
            "confidence_basis_points",
            "episode_ids",
        },
        where,
    )
    for field in ("candidate_id", "group_id", "subject", "predicate", "statement"):
        nonempty_string(candidate[field], f"{where}.{field}")
    confidence = candidate["confidence_basis_points"]
    if isinstance(confidence, bool) or not isinstance(confidence, int) or not 0 <= confidence <= 10_000:
        raise SystemExit(f"{where}.confidence_basis_points: expected 0..10000")
    episodes = string_list(candidate["episode_ids"], f"{where}.episode_ids")
    if len(episodes) != len(set(episodes)):
        raise SystemExit(f"{where}.episode_ids: duplicates are not canonical fixture input")
    object_value = candidate["object"]
    if not isinstance(object_value, dict) or "kind" not in object_value:
        raise SystemExit(f"{where}.object: expected a tagged object")
    if object_value["kind"] == "entity_ref":
        exact_keys(object_value, {"kind", "entity_id"}, f"{where}.object")
        nonempty_string(object_value["entity_id"], f"{where}.object.entity_id")
    elif object_value["kind"] == "literal" and not entity_only:
        exact_keys(object_value, {"kind", "value"}, f"{where}.object")
        nonempty_string(object_value["value"], f"{where}.object.value")
    else:
        raise SystemExit(f"{where}.object.kind: unsupported fixture object")
    return candidate


def normalize(statement: str) -> str:
    return re.sub(r"\s+", " ", statement.lower()).strip()


def upstream_retained_ids(candidates: list[dict[str, Any]]) -> list[str]:
    """Model only the upstream batch fast path; never union Episode references."""
    seen: set[tuple[str, str, str]] = set()
    retained: list[str] = []
    for candidate in candidates:
        key = (
            candidate["subject"],
            candidate["object"]["entity_id"],
            normalize(candidate["statement"]),
        )
        if key not in seen:
            seen.add(key)
            retained.append(candidate["candidate_id"])
    return retained


def factepoch_adapted_deduplicate(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Model FactEpoch-only group, literal, member, and provenance adaptations."""
    seen: dict[tuple[str, str, str, str], int] = {}
    output: list[dict[str, Any]] = []
    for candidate in candidates:
        object_value = candidate["object"]
        if object_value["kind"] == "literal":
            output.append(
                {
                    "retained_candidate_id": candidate["candidate_id"],
                    "member_candidate_ids": [candidate["candidate_id"]],
                    "episode_ids": sorted(set(candidate["episode_ids"])),
                    "parity_kinds": ["documented_adaptation"],
                }
            )
            continue
        key = (
            candidate["group_id"],
            candidate["subject"],
            object_value["entity_id"],
            normalize(candidate["statement"]),
        )
        if key not in seen:
            seen[key] = len(output)
            output.append(
                {
                    "retained_candidate_id": candidate["candidate_id"],
                    "member_candidate_ids": [candidate["candidate_id"]],
                    "episode_ids": list(candidate["episode_ids"]),
                    "parity_kinds": ["exact_upstream", "documented_adaptation"],
                }
            )
        else:
            retained = output[seen[key]]
            retained["member_candidate_ids"].append(candidate["candidate_id"])
            retained["episode_ids"].extend(candidate["episode_ids"])
    for retained in output:
        retained["episode_ids"] = sorted(set(retained["episode_ids"]))
    return output


def validate_exact(root: dict[str, Any]) -> None:
    exact_keys(
        root,
        {"fixture_schema", "parity_kind", "upstream", "runtime_profile", "normalization_cases", "dedup_cases"},
        "exact_upstream",
    )
    validate_common(root, "exact_upstream", "exact_upstream")
    normalization_cases = root["normalization_cases"]
    dedup_cases = root["dedup_cases"]
    if not isinstance(normalization_cases, list) or not normalization_cases:
        raise SystemExit("exact_upstream.normalization_cases: expected a non-empty list")
    if not isinstance(dedup_cases, list) or not dedup_cases:
        raise SystemExit("exact_upstream.dedup_cases: expected a non-empty list")
    unique_names(normalization_cases, "exact_upstream.normalization_cases")
    unique_names(dedup_cases, "exact_upstream.dedup_cases")
    for index, case_value in enumerate(normalization_cases):
        case = exact_keys(case_value, {"name", "input", "expected"}, f"normalization_cases[{index}]")
        nonempty_string(case["name"], f"normalization_cases[{index}].name")
        if not isinstance(case["input"], str) or not isinstance(case["expected"], str):
            raise SystemExit(f"normalization_cases[{index}]: input/expected must be strings")
        if normalize(case["input"]) != case["expected"]:
            raise SystemExit(f"normalization drift for {case['name']}")
    for index, case_value in enumerate(dedup_cases):
        case = exact_keys(
            case_value,
            {"name", "candidates", "expected_retained_candidate_ids"},
            f"dedup_cases[{index}]",
        )
        nonempty_string(case["name"], f"dedup_cases[{index}].name")
        if not isinstance(case["candidates"], list) or not case["candidates"]:
            raise SystemExit(f"dedup_cases[{index}].candidates: expected a non-empty list")
        candidates = [
            validate_candidate(value, f"dedup_cases[{index}].candidates[{candidate_index}]", entity_only=True)
            for candidate_index, value in enumerate(case["candidates"])
        ]
        ids = [candidate["candidate_id"] for candidate in candidates]
        if len(ids) != len(set(ids)):
            raise SystemExit(f"dedup_cases[{index}]: duplicate candidate IDs")
        expected = string_list(
            case["expected_retained_candidate_ids"],
            f"dedup_cases[{index}].expected_retained_candidate_ids",
        )
        if upstream_retained_ids(candidates) != expected:
            raise SystemExit(f"upstream dedup drift for {case['name']}")


def validate_expected_output(value: Any, where: str) -> dict[str, Any]:
    output = exact_keys(
        value,
        {"retained_candidate_id", "member_candidate_ids", "episode_ids", "parity_kinds"},
        where,
    )
    nonempty_string(output["retained_candidate_id"], f"{where}.retained_candidate_id")
    string_list(output["member_candidate_ids"], f"{where}.member_candidate_ids")
    string_list(output["episode_ids"], f"{where}.episode_ids")
    parity = string_list(output["parity_kinds"], f"{where}.parity_kinds")
    if parity not in (["documented_adaptation"], ["exact_upstream", "documented_adaptation"]):
        raise SystemExit(f"{where}.parity_kinds: noncanonical ordering or value")
    return output


def validate_adaptation(root: dict[str, Any]) -> None:
    exact_keys(
        root,
        {"fixture_schema", "parity_kind", "upstream", "runtime_profile", "cases"},
        "documented_adaptation",
    )
    validate_common(root, "documented_adaptation", "documented_adaptation")
    cases = root["cases"]
    if not isinstance(cases, list) or not cases:
        raise SystemExit("documented_adaptation.cases: expected a non-empty list")
    unique_names(cases, "documented_adaptation.cases")
    for index, case_value in enumerate(cases):
        case = exact_keys(case_value, {"name", "reason", "candidates", "expected"}, f"adaptation.cases[{index}]")
        nonempty_string(case["name"], f"adaptation.cases[{index}].name")
        nonempty_string(case["reason"], f"adaptation.cases[{index}].reason")
        if not isinstance(case["candidates"], list) or not case["candidates"]:
            raise SystemExit(f"adaptation.cases[{index}].candidates: expected a non-empty list")
        candidates = [
            validate_candidate(value, f"adaptation.cases[{index}].candidates[{candidate_index}]")
            for candidate_index, value in enumerate(case["candidates"])
        ]
        ids = [candidate["candidate_id"] for candidate in candidates]
        if len(ids) != len(set(ids)):
            raise SystemExit(f"adaptation.cases[{index}]: duplicate candidate IDs")
        expected_container = exact_keys(case["expected"], {"outputs"}, f"adaptation.cases[{index}].expected")
        if not isinstance(expected_container["outputs"], list) or not expected_container["outputs"]:
            raise SystemExit(f"adaptation.cases[{index}].expected.outputs: expected a non-empty list")
        expected = [
            validate_expected_output(value, f"adaptation.cases[{index}].expected.outputs[{output_index}]")
            for output_index, value in enumerate(expected_container["outputs"])
        ]
        if factepoch_adapted_deduplicate(candidates) != expected:
            raise SystemExit(f"FactEpoch adaptation drift for {case['name']}")


def moonbit_string(value: str) -> str:
    output = ['"']
    for char in value:
        code = ord(char)
        if char == '"':
            output.append('\\"')
        elif char == "\\":
            output.append("\\\\")
        elif char == "\n":
            output.append("\\n")
        elif char == "\r":
            output.append("\\r")
        elif char == "\t":
            output.append("\\t")
        elif 0x20 <= code <= 0x7E:
            output.append(char)
        else:
            output.append(f"\\u{{{code:x}}}")
    output.append('"')
    return "".join(output)


def moonbit_object(value: dict[str, Any]) -> str:
    if value["kind"] == "entity_ref":
        return f"EntityRef(EntityId::new({moonbit_string(value['entity_id'])}))"
    return f"Literal({moonbit_string(value['value'])})"


def candidate_expression(candidate: dict[str, Any]) -> list[str]:
    episodes = ", ".join(
        f"EpisodeId::new({moonbit_string(value)})" for value in candidate["episode_ids"]
    )
    return [
        "    generated_graphiti_candidate(",
        f"      {moonbit_string(candidate['candidate_id'])},",
        f"      {moonbit_string(candidate['group_id'])},",
        f"      {moonbit_string(candidate['subject'])},",
        f"      {moonbit_string(candidate['predicate'])},",
        f"      {moonbit_object(candidate['object'])},",
        f"      {moonbit_string(candidate['statement'])},",
        f"      {candidate['confidence_basis_points']},",
        f"      [{episodes}],",
        "    ),",
    ]


def render_dedup_test(name: str, candidates: list[dict[str, Any]], expected: list[dict[str, Any]]) -> list[str]:
    lines = ["///|", f"test {moonbit_string('generated Graphiti fixture ' + name)} {{", "  let report = deduplicate_candidates(["]
    for candidate in candidates:
        lines.extend(candidate_expression(candidate))
    lines.extend(["  ])", "  let outputs = report.candidates()", f"  inspect(outputs.length(), content={moonbit_string(str(len(expected)))})"])
    for index, item in enumerate(expected):
        retained = moonbit_string(item["retained_candidate_id"])
        members = moonbit_string(",".join(item["member_candidate_ids"]))
        episodes = moonbit_string(",".join(item["episode_ids"]))
        lines.extend(
            [
                "  inspect(",
                f"    outputs[{index}].retained_candidate().candidate_id().value(),",
                f"    content={retained},",
                "  )",
                "  inspect(",
                f"    outputs[{index}].member_candidate_ids().map(id => id.value()).join(\",\"),",
                f"    content={members},",
                "  )",
                "  inspect(",
                f"    outputs[{index}].episode_ids().map(id => id.value()).join(\",\"),",
                f"    content={episodes},",
                "  )",
                f"  let kinds_{index} = outputs[{index}].parity_kinds()",
                f"  inspect(kinds_{index}.length(), content={moonbit_string(str(len(item['parity_kinds'])))})",
            ]
        )
        for parity_index, parity in enumerate(item["parity_kinds"]):
            variant = "ExactUpstream" if parity == "exact_upstream" else "DocumentedAdaptation"
            lines.append(f"  inspect(kinds_{index}[{parity_index}] == {variant}, content=\"true\")")
    lines.append("}")
    return lines


def render_exact_dedup_test(
    name: str, candidates: list[dict[str, Any]], expected_retained: list[str]
) -> list[str]:
    lines = [
        "///|",
        f"test {moonbit_string('generated Graphiti fixture ' + name)} {{",
        "  let report = deduplicate_candidates([",
    ]
    for candidate in candidates:
        lines.extend(candidate_expression(candidate))
    lines.extend(
        [
            "  ])",
            "  inspect(",
            "    report",
            "    .candidates()",
            "    .map(value => value.retained_candidate().candidate_id().value())",
            "    .join(\",\"),",
            f"    content={moonbit_string(','.join(expected_retained))},",
            "  )",
            "}",
        ]
    )
    return lines


def render_tests(exact: dict[str, Any], adaptation: dict[str, Any]) -> str:
    lines = [
        "// SPDX-License-Identifier: Apache-2.0",
        "// @generated by compat/python/oracle_graphiti_v0301.py; DO NOT EDIT.",
        "// Generated fixture tests are excluded from handwritten-test LOC.",
        "",
        "///|",
        "fn generated_graphiti_candidate(",
        "  id : String,",
        "  group : String,",
        "  subject : String,",
        "  predicate : String,",
        "  object : FactObject,",
        "  statement : String,",
        "  confidence : Int,",
        "  episodes : Array[EpisodeId],",
        ") -> CandidateFact raise MemoryError {",
        "  CandidateFact::new(",
        "    CandidateId::new(id),",
        "    GroupId::new(group),",
        "    EntityId::new(subject),",
        "    predicate,",
        "    object,",
        "    statement,",
        "    confidence,",
        "    episodes,",
        "  )",
        "}",
        "",
        "///|",
        "test \"generated Graphiti normalization vectors\" {",
    ]
    for case in exact["normalization_cases"]:
        one_line = (
            f"  inspect(graphiti_normalize_statement({moonbit_string(case['input'])}), "
            f"content={moonbit_string(case['expected'])})"
        )
        if len(one_line) <= 80:
            lines.append(one_line)
        else:
            lines.extend(
                [
                    "  inspect(",
                    f"    graphiti_normalize_statement({moonbit_string(case['input'])}),",
                    f"    content={moonbit_string(case['expected'])},",
                    "  )",
                ]
            )
    lines.append("}")
    for case in exact["dedup_cases"]:
        lines.extend(
            [
                "",
                *render_exact_dedup_test(
                    case["name"],
                    case["candidates"],
                    case["expected_retained_candidate_ids"],
                ),
            ]
        )
    for case in adaptation["cases"]:
        lines.extend(["", *render_dedup_test(case["name"], case["candidates"], case["expected"]["outputs"])])
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="byte-compare the generated MoonBit tests")
    args = parser.parse_args()
    require_profile()
    exact = load_fixture("exact_upstream.json")
    adaptation = load_fixture("documented_adaptation.json")
    validate_exact(exact)
    validate_adaptation(adaptation)
    body = render_tests(exact, adaptation).encode("utf-8")
    if args.check:
        if not GENERATED_TEST.exists() or GENERATED_TEST.read_bytes() != body:
            raise SystemExit(f"generated fixture tests are stale: {GENERATED_TEST}")
        action = "checked"
    else:
        GENERATED_TEST.write_bytes(body)
        action = "wrote"
    print(f"{action}=2 fixtures generated_test={GENERATED_TEST.name}")


if __name__ == "__main__":
    main()
