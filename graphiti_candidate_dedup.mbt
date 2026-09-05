// SPDX-License-Identifier: Apache-2.0
// Portions derived from getzep/graphiti.
// Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
// Copyright 2024, Zep Software, Inc.
// Translated and modified for MoonBit in 2026.

///|
priv struct EntityCandidateKey {
  group_id : GroupId
  subject : EntityId
  object : EntityId
  normalized_statement : String
} derive(Eq, Hash)

///|
fn initial_deduplicated_candidate(
  candidate : CandidateFact,
  parity_kinds : Array[ParityKind],
) -> DeduplicatedCandidate {
  {
    retained_candidate: candidate,
    member_candidate_ids: [candidate.candidate_id()],
    episode_ids: candidate.episode_ids(),
    parity_kinds,
  }
}

///|
fn merge_candidate(
  retained : DeduplicatedCandidate,
  candidate : CandidateFact,
) -> DeduplicatedCandidate {
  let member_candidate_ids = retained.member_candidate_ids
  member_candidate_ids.push(candidate.candidate_id())
  let episode_ids = retained.episode_ids
  episode_ids.append(candidate.episode_ids())
  {
    retained_candidate: retained.retained_candidate,
    member_candidate_ids,
    episode_ids,
    parity_kinds: retained.parity_kinds,
  }
}

///|
fn finalize_episode_union(
  candidate : DeduplicatedCandidate,
) -> DeduplicatedCandidate {
  let episode_ids = candidate.episode_ids
  episode_ids.sort()
  episode_ids.dedup()
  {
    retained_candidate: candidate.retained_candidate,
    member_candidate_ids: candidate.member_candidate_ids,
    episode_ids,
    parity_kinds: candidate.parity_kinds,
  }
}

///|
/// Deduplicate pre-ID candidates using the pinned Graphiti entity-edge key.
///
/// Maps are lookup-only: output order is always the input encounter order of
/// retained representatives. Literal candidates intentionally pass through.
pub fn deduplicate_candidates(
  candidates : Array[CandidateFact],
) -> CandidateDedupReport raise MemoryError {
  let seen_ids : Map[CandidateId, Bool] = Map([])
  let entity_key_positions : Map[EntityCandidateKey, Int] = Map([])
  let output : Array[DeduplicatedCandidate] = []
  let mut collapsed_count = 0
  for candidate in candidates {
    if seen_ids.contains(candidate.candidate_id()) {
      raise DuplicateCandidateId(candidate.candidate_id())
    }
    seen_ids.set(candidate.candidate_id(), true)
    match candidate.object() {
      Literal(_) =>
        output.push(
          initial_deduplicated_candidate(candidate, [DocumentedAdaptation]),
        )
      EntityRef(object) => {
        let key = {
          group_id: candidate.group_id(),
          subject: candidate.subject(),
          object,
          normalized_statement: graphiti_normalize_statement(
            candidate.statement(),
          ),
        }
        match entity_key_positions.get(key) {
          Some(position) => {
            output[position] = merge_candidate(output[position], candidate)
            collapsed_count += 1
          }
          None => {
            entity_key_positions.set(key, output.length())
            output.push(
              initial_deduplicated_candidate(candidate, [
                ExactUpstream,
                DocumentedAdaptation,
              ]),
            )
          }
        }
      }
    }
  }
  for index = 0; index < output.length(); index = index + 1 {
    output[index] = finalize_episode_union(output[index])
  }
  { candidates: output, input_count: candidates.length(), collapsed_count }
}
