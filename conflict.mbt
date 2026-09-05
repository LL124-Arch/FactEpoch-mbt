// SPDX-License-Identifier: Apache-2.0

///|
/// The explicit outcome selected after comparing a candidate with prior facts.
pub(all) enum ConflictAction {
  RejectCandidate
  SupersedeExisting
  AdmitParallel
} derive(Eq)

///|
fn normalized_fact_id_set(
  ids : Array[FactId],
  field : String,
) -> Array[FactId] raise MemoryError {
  if ids.is_empty() {
    raise InvalidField(field, "must contain at least one fact ID")
  }
  let normalized = ids.copy()
  normalized.sort()
  for index in 1..<normalized.length() {
    if normalized[index - 1] == normalized[index] {
      raise DuplicateFactReference(normalized[index])
    }
  }
  normalized
}

///|
/// An immutable audit record for an explicit conflict decision.
pub struct ConflictDecision {
  priv actor : String
  priv rationale : String
  priv candidate_fact_id : FactId
  priv prior_fact_ids : Array[FactId]
  priv action : ConflictAction
} derive(Eq)

///|
pub fn ConflictDecision::new(
  actor : String,
  rationale : String,
  candidate_fact_id : FactId,
  prior_fact_ids : Array[FactId],
  action : ConflictAction,
) -> ConflictDecision raise MemoryError {
  require_nonempty("actor", actor)
  require_nonempty("rationale", rationale)
  let normalized_prior = normalized_fact_id_set(
    prior_fact_ids, "prior_fact_ids",
  )
  if normalized_prior.contains(candidate_fact_id) {
    raise ConflictDecisionMismatch("candidate_in_prior")
  }
  {
    actor,
    rationale,
    candidate_fact_id,
    prior_fact_ids: normalized_prior,
    action,
  }
}

///|
pub fn ConflictDecision::actor(self : ConflictDecision) -> String {
  self.actor
}

///|
pub fn ConflictDecision::rationale(self : ConflictDecision) -> String {
  self.rationale
}

///|
pub fn ConflictDecision::candidate_fact_id(self : ConflictDecision) -> FactId {
  self.candidate_fact_id
}

///|
pub fn ConflictDecision::prior_fact_ids(
  self : ConflictDecision,
) -> Array[FactId] {
  self.prior_fact_ids.copy()
}

///|
pub fn ConflictDecision::action(self : ConflictDecision) -> ConflictAction {
  self.action
}

///|
/// The terminal reason attached to a fact lifecycle.
pub(all) enum FactClosureCause {
  SupersededBy(FactId, ConflictDecision)
  Retracted(String)
} derive(Eq)

///|
/// One immutable terminal lifecycle transition for a fact.
pub struct FactClosure {
  priv event_id : EventId
  priv recorded_at : Timestamp
  priv effective_at : Timestamp
  priv cause : FactClosureCause
} derive(Eq)

///|
fn FactClosure::make(
  event_id : EventId,
  recorded_at : Timestamp,
  effective_at : Timestamp,
  cause : FactClosureCause,
) -> FactClosure {
  { event_id, recorded_at, effective_at, cause }
}

///|
pub fn FactClosure::event_id(self : FactClosure) -> EventId {
  self.event_id
}

///|
pub fn FactClosure::recorded_at(self : FactClosure) -> Timestamp {
  self.recorded_at
}

///|
pub fn FactClosure::effective_at(self : FactClosure) -> Timestamp {
  self.effective_at
}

///|
pub fn FactClosure::cause(self : FactClosure) -> FactClosureCause {
  self.cause
}

///|
/// Why a known fact is or is not visible at a valid-time point.
pub(all) enum FactVisibility {
  Visible
  BeforeValidFrom
  EndedByAssertion
  EndedBySupersession(FactId)
  EndedByRetraction
} derive(Eq)

///|
/// A content-free structural guard category for supersession failures.
pub(all) enum SupersessionGuard {
  GroupGuard
  SubjectGuard
  PredicateGuard
  ObjectKindGuard
  DirectedEndpointGuard
  IntervalOverlapGuard
} derive(Eq, @debug.Debug)
