// SPDX-License-Identifier: Apache-2.0
// Portions derived from getzep/graphiti.
// Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
// Copyright 2024, Zep Software, Inc.
// Translated and modified for MoonBit in 2026.

///|
fn finite_double(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// Calculate cosine similarity using the pinned Graphiti dot/L2 formula.
/// Empty and zero-norm vectors return positive zero.
pub fn cosine_similarity(
  left : ArrayView[Double],
  right : ArrayView[Double],
) -> Double raise MemoryError {
  if left.length() != right.length() {
    raise InvalidVectorDimensions(left.length(), right.length())
  }
  let mut dot = 0.0
  let mut left_squared = 0.0
  let mut right_squared = 0.0
  for index in 0..<left.length() {
    let left_value = left[index]
    let right_value = right[index]
    if !finite_double(left_value) {
      raise NonFiniteVectorValue(LeftVector, index)
    }
    if !finite_double(right_value) {
      raise NonFiniteVectorValue(RightVector, index)
    }
    let product = left_value * right_value
    let left_square = left_value * left_value
    let right_square = right_value * right_value
    if !finite_double(product) ||
      !finite_double(left_square) ||
      !finite_double(right_square) {
      raise NonFiniteVectorComputation
    }
    dot += product
    left_squared += left_square
    right_squared += right_square
    if !finite_double(dot) ||
      !finite_double(left_squared) ||
      !finite_double(right_squared) {
      raise NonFiniteVectorComputation
    }
  }
  if left_squared == 0.0 || right_squared == 0.0 {
    return 0.0
  }
  let denominator = left_squared.sqrt() * right_squared.sqrt()
  if !finite_double(denominator) || denominator == 0.0 {
    raise NonFiniteVectorComputation
  }
  let result = dot / denominator
  if !finite_double(result) {
    raise NonFiniteVectorComputation
  }
  result
}

///|
/// One candidate at its zero-based position in an external ranked source.
pub struct RankedCandidate {
  priv fact_id : FactId
  priv zero_based_rank : Int
  priv source_score : Double?
} derive(Eq)

///|
pub fn RankedCandidate::new(
  fact_id : FactId,
  zero_based_rank : Int,
  source_score : Double?,
) -> RankedCandidate raise MemoryError {
  if zero_based_rank < 0 {
    raise InvalidCandidateRank(fact_id, zero_based_rank)
  }
  match source_score {
    Some(score) if !finite_double(score) => raise NonFiniteRankedScore(fact_id)
    _ => ()
  }
  { fact_id, zero_based_rank, source_score }
}

///|
pub fn RankedCandidate::fact_id(self : RankedCandidate) -> FactId {
  self.fact_id
}

///|
pub fn RankedCandidate::zero_based_rank(self : RankedCandidate) -> Int {
  self.zero_based_rank
}

///|
pub fn RankedCandidate::source_score(self : RankedCandidate) -> Double? {
  self.source_score
}

///|
fn compare_ranked_candidate(
  left : RankedCandidate,
  right : RankedCandidate,
) -> Int {
  if left.zero_based_rank < right.zero_based_rank {
    -1
  } else if left.zero_based_rank > right.zero_based_rank {
    1
  } else if left.fact_id < right.fact_id {
    -1
  } else if left.fact_id > right.fact_id {
    1
  } else {
    0
  }
}

///|
/// A named, canonical ranking contributed by one retrieval source.
pub struct RankedCandidateList {
  priv source : String
  priv candidates : Array[RankedCandidate]
}

///|
pub fn RankedCandidateList::new(
  source : String,
  candidates : Array[RankedCandidate],
) -> RankedCandidateList raise MemoryError {
  if source.trim().is_empty() {
    raise InvalidRankSource
  }
  let normalized = candidates.copy()
  normalized.sort_by(compare_ranked_candidate)
  let seen : Map[FactId, Bool] = Map([])
  for index, candidate in normalized {
    if seen.contains(candidate.fact_id) {
      raise DuplicateRankedCandidate(candidate.fact_id)
    }
    seen.set(candidate.fact_id, true)
    if candidate.zero_based_rank != index {
      if index > 0 &&
        candidate.zero_based_rank == normalized[index - 1].zero_based_rank {
        raise DuplicateCandidateRank(candidate.zero_based_rank)
      }
      raise InvalidCandidateRank(candidate.fact_id, candidate.zero_based_rank)
    }
  }
  { source, candidates: normalized }
}

///|
pub fn RankedCandidateList::source(self : RankedCandidateList) -> String {
  self.source
}

///|
pub fn RankedCandidateList::candidates(
  self : RankedCandidateList,
) -> Array[RankedCandidate] {
  self.candidates.copy()
}

///|
pub struct RrfConfig {
  priv rank_constant : Int
  priv minimum_score : Double
}

///|
pub fn RrfConfig::new(
  rank_constant : Int,
  minimum_score : Double,
) -> RrfConfig raise MemoryError {
  if rank_constant <= 0 {
    raise InvalidRankConstant(rank_constant)
  }
  if !finite_double(minimum_score) {
    raise InvalidMinimumScore
  }
  { rank_constant, minimum_score }
}

///|
pub fn RrfConfig::default() -> RrfConfig {
  { rank_constant: 1, minimum_score: 0.0 }
}

///|
pub fn RrfConfig::rank_constant(self : RrfConfig) -> Int {
  self.rank_constant
}

///|
pub fn RrfConfig::minimum_score(self : RrfConfig) -> Double {
  self.minimum_score
}

///|
pub struct RankContribution {
  priv source : String
  priv zero_based_rank : Int
  priv contribution : Double
} derive(Eq)

///|
pub fn RankContribution::source(self : RankContribution) -> String {
  self.source
}

///|
pub fn RankContribution::zero_based_rank(self : RankContribution) -> Int {
  self.zero_based_rank
}

///|
pub fn RankContribution::contribution(self : RankContribution) -> Double {
  self.contribution
}

///|
pub struct FusedCandidate {
  priv fact_id : FactId
  priv score : Double
  priv contributions : Array[RankContribution]
} derive(Eq)

///|
pub fn FusedCandidate::fact_id(self : FusedCandidate) -> FactId {
  self.fact_id
}

///|
pub fn FusedCandidate::score(self : FusedCandidate) -> Double {
  self.score
}

///|
pub fn FusedCandidate::contributions(
  self : FusedCandidate,
) -> Array[RankContribution] {
  self.contributions.copy()
}

///|
fn compare_ranked_lists(
  left : RankedCandidateList,
  right : RankedCandidateList,
) -> Int {
  left.source.compare(right.source)
}

///|
fn compare_fused(left : FusedCandidate, right : FusedCandidate) -> Int {
  if left.score > right.score {
    -1
  } else if left.score < right.score {
    1
  } else if left.fact_id < right.fact_id {
    -1
  } else if left.fact_id > right.fact_id {
    1
  } else {
    0
  }
}

///|
/// Fuse canonical rankings with Graphiti's `1 / (rank + k)` formula.
pub fn reciprocal_rank_fusion(
  lists : Array[RankedCandidateList],
  config : RrfConfig,
) -> Array[FusedCandidate] raise MemoryError {
  let canonical = lists.copy()
  canonical.sort_by(compare_ranked_lists)
  for index in 1..<canonical.length() {
    if canonical[index - 1].source == canonical[index].source {
      raise DuplicateRankSource
    }
  }
  let output : Array[FusedCandidate] = []
  let positions : Map[FactId, Int] = Map([])
  for list in canonical {
    for candidate in list.candidates {
      let denominator = Double::from_int(candidate.zero_based_rank) +
        Double::from_int(config.rank_constant)
      let contribution = 1.0 / denominator
      match positions.get(candidate.fact_id) {
        None => {
          positions.set(candidate.fact_id, output.length())
          output.push({
            fact_id: candidate.fact_id,
            score: contribution,
            contributions: [
              {
                source: list.source,
                zero_based_rank: candidate.zero_based_rank,
                contribution,
              },
            ],
          })
        }
        Some(position) => {
          let existing = output[position]
          let contributions = existing.contributions.copy()
          contributions.push({
            source: list.source,
            zero_based_rank: candidate.zero_based_rank,
            contribution,
          })
          output[position] = {
            fact_id: existing.fact_id,
            score: existing.score + contribution,
            contributions,
          }
        }
      }
    }
  }
  let retained : Array[FusedCandidate] = []
  for candidate in output {
    if candidate.score >= config.minimum_score {
      retained.push(candidate)
    }
  }
  retained.sort_by(compare_fused)
  retained
}
