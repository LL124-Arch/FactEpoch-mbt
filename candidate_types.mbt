// SPDX-License-Identifier: Apache-2.0

///|
/// Whether a candidate behavior is identical to the pinned Graphiti helper or
/// is an intentional FactEpoch adaptation.
pub(all) enum ParityKind {
  ExactUpstream
  DocumentedAdaptation
} derive(Eq)

///|
/// A pre-ID extraction candidate. It is not an authoritative fact.
pub struct CandidateFact {
  priv candidate_id : CandidateId
  priv group_id : GroupId
  priv subject : EntityId
  priv predicate : String
  priv object : FactObject
  priv statement : String
  priv confidence_basis_points : Int
  priv episode_ids : Array[EpisodeId]
} derive(Eq)

///|
/// Construct a candidate while taking defensive ownership of source IDs.
pub fn CandidateFact::new(
  candidate_id : CandidateId,
  group_id : GroupId,
  subject : EntityId,
  predicate : String,
  object : FactObject,
  statement : String,
  confidence_basis_points : Int,
  episode_ids : Array[EpisodeId],
) -> CandidateFact raise MemoryError {
  require_nonempty("predicate", predicate)
  require_nonempty("statement", statement)
  match object {
    Literal(value) => require_nonempty("object.literal", value)
    EntityRef(_) => ()
  }
  if confidence_basis_points < 0 || confidence_basis_points > 10_000 {
    raise InvalidConfidence(confidence_basis_points)
  }
  if episode_ids.is_empty() {
    raise InvalidField("episode_ids", "must contain at least one episode")
  }
  let normalized_episode_ids = episode_ids.copy()
  normalized_episode_ids.sort()
  normalized_episode_ids.dedup()
  {
    candidate_id,
    group_id,
    subject,
    predicate,
    object,
    statement,
    confidence_basis_points,
    episode_ids: normalized_episode_ids,
  }
}

///|
pub fn CandidateFact::candidate_id(self : CandidateFact) -> CandidateId {
  self.candidate_id
}

///|
pub fn CandidateFact::group_id(self : CandidateFact) -> GroupId {
  self.group_id
}

///|
pub fn CandidateFact::subject(self : CandidateFact) -> EntityId {
  self.subject
}

///|
pub fn CandidateFact::predicate(self : CandidateFact) -> String {
  self.predicate
}

///|
pub fn CandidateFact::object(self : CandidateFact) -> FactObject {
  self.object
}

///|
pub fn CandidateFact::statement(self : CandidateFact) -> String {
  self.statement
}

///|
pub fn CandidateFact::confidence_basis_points(self : CandidateFact) -> Int {
  self.confidence_basis_points
}

///|
/// Return canonical source IDs as a defensive copy.
pub fn CandidateFact::episode_ids(self : CandidateFact) -> Array[EpisodeId] {
  self.episode_ids.copy()
}

///|
/// One retained candidate and the complete membership/source record for its
/// equivalence class.
pub struct DeduplicatedCandidate {
  priv retained_candidate : CandidateFact
  priv member_candidate_ids : Array[CandidateId]
  priv episode_ids : Array[EpisodeId]
  priv parity_kinds : Array[ParityKind]
} derive(Eq)

///|
pub fn DeduplicatedCandidate::retained_candidate(
  self : DeduplicatedCandidate,
) -> CandidateFact {
  self.retained_candidate
}

///|
/// Return member IDs in deterministic encounter order.
pub fn DeduplicatedCandidate::member_candidate_ids(
  self : DeduplicatedCandidate,
) -> Array[CandidateId] {
  self.member_candidate_ids.copy()
}

///|
/// Return the sorted union of source episode IDs.
pub fn DeduplicatedCandidate::episode_ids(
  self : DeduplicatedCandidate,
) -> Array[EpisodeId] {
  self.episode_ids.copy()
}

///|
pub fn DeduplicatedCandidate::parity_kinds(
  self : DeduplicatedCandidate,
) -> Array[ParityKind] {
  self.parity_kinds.copy()
}

///|
/// Materialize an authoritative fact only after its caller allocates identity
/// and valid time. Aggregated episode sources become validated provenance.
pub fn DeduplicatedCandidate::materialize(
  self : DeduplicatedCandidate,
  fact_id : FactId,
  valid_from : Timestamp,
  valid_to : Timestamp?,
  evidence : Array[EvidenceSpan],
  extractor : String?,
) -> FactAssertion raise MemoryError {
  FactAssertion::new(
    fact_id,
    self.retained_candidate.group_id(),
    self.retained_candidate.subject(),
    self.retained_candidate.predicate(),
    self.retained_candidate.object(),
    self.retained_candidate.statement(),
    valid_from,
    valid_to,
    self.retained_candidate.confidence_basis_points(),
    Provenance::new(self.episode_ids, evidence, extractor),
  )
}

///|
/// Deterministic summary of one candidate-only deduplication pass.
pub struct CandidateDedupReport {
  priv candidates : Array[DeduplicatedCandidate]
  priv input_count : Int
  priv collapsed_count : Int
}

///|
pub fn CandidateDedupReport::candidates(
  self : CandidateDedupReport,
) -> Array[DeduplicatedCandidate] {
  self.candidates.copy()
}

///|
pub fn CandidateDedupReport::input_count(self : CandidateDedupReport) -> Int {
  self.input_count
}

///|
pub fn CandidateDedupReport::output_count(self : CandidateDedupReport) -> Int {
  self.candidates.length()
}

///|
pub fn CandidateDedupReport::collapsed_count(
  self : CandidateDedupReport,
) -> Int {
  self.collapsed_count
}
