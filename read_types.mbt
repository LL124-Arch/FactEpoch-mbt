// SPDX-License-Identifier: Apache-2.0

///|
/// Optional structural filters applied after bitemporal projection.
pub struct FactFilter {
  priv group_id : GroupId?
  priv subject : EntityId?
  priv predicate_key : String?
  priv object : FactObject?
  priv provenance_episode : EpisodeId?
}

///|
/// Construct an unconstrained fact filter.
pub fn FactFilter::all() -> FactFilter {
  {
    group_id: None,
    subject: None,
    predicate_key: None,
    object: None,
    provenance_episode: None,
  }
}

///|
/// Construct a structural filter. Predicate spelling is normalized only for
/// matching and never replaces the source spelling stored on an assertion.
pub fn FactFilter::new(
  group_id? : GroupId,
  subject? : EntityId,
  predicate? : String,
  object? : FactObject,
  provenance_episode? : EpisodeId,
) -> FactFilter raise MemoryError {
  let normalized_predicate = match predicate {
    Some(value) => {
      let key = predicate_key(value)
      if key.is_empty() {
        raise InvalidField("predicate", "must not normalize to empty")
      }
      Some(key)
    }
    None => None
  }
  {
    group_id,
    subject,
    predicate_key: normalized_predicate,
    object,
    provenance_episode,
  }
}

///|
/// A point lookup over valid time and system-known time.
pub struct FactQuery {
  priv valid_at : Timestamp
  priv known_at : Timestamp
  priv filter : FactFilter
  priv limit : Int
}

///|
/// Construct a query with a bounded result limit.
pub fn FactQuery::new(
  valid_at : Timestamp,
  known_at : Timestamp,
  filter : FactFilter,
  limit? : Int = 100,
) -> FactQuery raise MemoryError {
  if limit < 1 || limit > 10_000 {
    raise InvalidLimit(limit)
  }
  { valid_at, known_at, filter, limit }
}

///|
/// A normalized group-and-subject predicate slot used for history lookup.
pub struct FactSlot {
  priv group_id : GroupId
  priv subject : EntityId
  priv predicate_key : String
} derive(Eq)

///|
pub fn FactSlot::new(
  group_id : GroupId,
  subject : EntityId,
  predicate : String,
) -> FactSlot raise MemoryError {
  let key = predicate_key(predicate)
  if key.is_empty() {
    raise InvalidField("predicate", "must not normalize to empty")
  }
  { group_id, subject, predicate_key: key }
}

///|
pub fn FactSlot::group_id(self : FactSlot) -> GroupId {
  self.group_id
}

///|
pub fn FactSlot::subject(self : FactSlot) -> EntityId {
  self.subject
}

///|
pub fn FactSlot::predicate_key(self : FactSlot) -> String {
  self.predicate_key
}

///|
/// Select one fact identity or every version in a normalized fact slot.
pub(all) enum HistoryTarget {
  ByFactId(FactId)
  BySlot(FactSlot)
} derive(Eq)

///|
/// A closed knowledge-time activation window.
pub struct HistoryQuery {
  priv target : HistoryTarget
  priv from_known_at : Timestamp
  priv to_known_at : Timestamp
  priv limit : Int
}

///|
pub fn HistoryQuery::new(
  target : HistoryTarget,
  from_known_at : Timestamp,
  to_known_at : Timestamp,
  limit? : Int = 100,
) -> HistoryQuery raise MemoryError {
  if from_known_at > to_known_at {
    raise InvalidTimeRange("history.known_at", from_known_at, to_known_at)
  }
  if limit < 1 || limit > 10_000 {
    raise InvalidLimit(limit)
  }
  { target, from_known_at, to_known_at, limit }
}

///|
/// The one time dimension varied by a fact-set comparison.
pub(all) enum DiffAxis {
  AcrossKnowledge(Timestamp, Timestamp, Timestamp)
  AcrossValidity(Timestamp, Timestamp, Timestamp)
} derive(Eq)

///|
/// A structural diff request. Axis parameters are respectively
/// `(valid_at, from_known_at, to_known_at)` and
/// `(known_at, from_valid_at, to_valid_at)`.
pub struct DiffQuery {
  priv axis : DiffAxis
  priv filter : FactFilter
}

///|
pub fn DiffQuery::new(
  axis : DiffAxis,
  filter : FactFilter,
) -> DiffQuery raise MemoryError {
  match axis {
    AcrossKnowledge(_, from_known_at, to_known_at) =>
      if from_known_at > to_known_at {
        raise InvalidTimeRange("diff.known_at", from_known_at, to_known_at)
      }
    AcrossValidity(_, from_valid_at, to_valid_at) =>
      if from_valid_at > to_valid_at {
        raise InvalidTimeRange("diff.valid_at", from_valid_at, to_valid_at)
      }
  }
  { axis, filter }
}

///|
/// An immutable query projection retaining its first activation envelope.
///
/// The integer score is assertion confidence for this milestone. Search
/// adapters add ranked floating-point scores in a later milestone.
pub struct FactView {
  priv fact : FactAssertion
  priv predicate_key : String
  priv activation_event_id : EventId
  priv activation_recorded_at : Timestamp
  priv effective_valid_to : Timestamp?
  priv score_basis_points : Int
} derive(Eq)

///|
pub fn FactView::fact(self : FactView) -> FactAssertion {
  self.fact
}

///|
pub fn FactView::predicate_key(self : FactView) -> String {
  self.predicate_key
}

///|
pub fn FactView::activation_event_id(self : FactView) -> EventId {
  self.activation_event_id
}

///|
pub fn FactView::activation_recorded_at(self : FactView) -> Timestamp {
  self.activation_recorded_at
}

///|
/// Return the effective exclusive upper valid-time bound. It currently equals
/// the assertion bound; explicit closure events will be projected here later.
pub fn FactView::effective_valid_to(self : FactView) -> Timestamp? {
  self.effective_valid_to
}

///|
pub fn FactView::score_basis_points(self : FactView) -> Int {
  self.score_basis_points
}

///|
/// Stable FactId partitions between two bitemporal projections.
pub struct FactDiff {
  priv added : Array[FactView]
  priv removed : Array[FactView]
  priv unchanged : Array[FactView]
}

///|
pub fn FactDiff::added(self : FactDiff) -> Array[FactView] {
  self.added.copy()
}

///|
pub fn FactDiff::removed(self : FactDiff) -> Array[FactView] {
  self.removed.copy()
}

///|
pub fn FactDiff::unchanged(self : FactDiff) -> Array[FactView] {
  self.unchanged.copy()
}
