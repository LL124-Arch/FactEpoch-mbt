// SPDX-License-Identifier: Apache-2.0

///|
fn fact_matches_filter(fact : FactAssertion, filter : FactFilter) -> Bool {
  match filter.group_id {
    Some(group_id) if fact.group_id() != group_id => return false
    _ => ()
  }
  match filter.subject {
    Some(subject) if fact.subject() != subject => return false
    _ => ()
  }
  match filter.predicate_key {
    Some(key) if predicate_key(fact.predicate()) != key => return false
    _ => ()
  }
  match filter.object {
    Some(object) if fact.object() != object => return false
    _ => ()
  }
  match filter.provenance_episode {
    Some(episode_id) if !fact.provenance().episode_ids().contains(episode_id) =>
      return false
    _ => ()
  }
  true
}

///|
fn stored_fact_view(stored : StoredFact) -> FactView {
  let fact = stored.assertion
  let effective_valid_to = match (fact.valid_to(), stored.closure) {
    (None, None) => None
    (Some(asserted), None) => Some(asserted)
    (None, Some(closure)) => Some(closure.effective_at())
    (Some(asserted), Some(closure)) =>
      Some(
        if asserted <= closure.effective_at() {
          asserted
        } else {
          closure.effective_at()
        },
      )
  }
  {
    fact,
    predicate_key: predicate_key(fact.predicate()),
    activation_event_id: stored.activation_event_id,
    activation_recorded_at: stored.activation_recorded_at,
    effective_valid_to,
    closure: stored.closure,
    score_basis_points: fact.confidence_basis_points(),
  }
}

///|
fn compare_fact_view(left : FactView, right : FactView) -> Int {
  if left.score_basis_points > right.score_basis_points {
    -1
  } else if left.score_basis_points < right.score_basis_points {
    1
  } else if left.fact.valid_from() > right.fact.valid_from() {
    -1
  } else if left.fact.valid_from() < right.fact.valid_from() {
    1
  } else if left.fact.id() < right.fact.id() {
    -1
  } else if left.fact.id() > right.fact.id() {
    1
  } else {
    0
  }
}

///|
fn project_at_known(
  graph : MemoryGraph,
  known_at : Timestamp,
) -> Result[MemoryGraph, MemoryError] {
  let prefix : Array[RecordedEvent] = []
  for envelope in graph.events {
    if envelope.recorded_at() > known_at {
      break
    }
    prefix.push(envelope)
  }
  MemoryGraph::replay(prefix)
}

///|
fn filter_at_valid(
  projected : MemoryGraph,
  valid_at : Timestamp,
  filter : FactFilter,
) -> Array[FactView] {
  let visible : Array[FactView] = []
  for stored in projected.facts {
    let view = stored_fact_view(stored)
    let after_start = valid_at >= stored.assertion.valid_from()
    let before_end = match view.effective_valid_to() {
      None => true
      Some(end) => valid_at < end
    }
    if after_start &&
      before_end &&
      fact_matches_filter(stored.assertion, filter) {
      visible.push(view)
    }
  }
  visible.sort_by(compare_fact_view)
  visible
}

///|
fn history_target_matches(fact : FactAssertion, target : HistoryTarget) -> Bool {
  match target {
    ByFactId(id) => fact.id() == id
    BySlot(slot) =>
      fact.group_id() == slot.group_id &&
      fact.subject() == slot.subject &&
      predicate_key(fact.predicate()) == slot.predicate_key
  }
}

///|
fn take_fact_views(views : Array[FactView], limit : Int) -> Array[FactView] {
  if views.length() <= limit {
    views
  } else {
    let limited : Array[FactView] = []
    for index in 0..<limit {
      limited.push(views[index])
    }
    limited
  }
}

///|
/// Replay the inclusive known-time prefix, then filter facts at valid time.
pub fn MemoryGraph::query(
  self : MemoryGraph,
  query : FactQuery,
) -> Result[Array[FactView], MemoryError] {
  match project_at_known(self, query.known_at) {
    Err(error) => Err(error)
    Ok(projected) =>
      Ok(
        take_fact_views(
          filter_at_valid(projected, query.valid_at, query.filter),
          query.limit,
        ),
      )
  }
}

///|
/// Replay through the upper bound, then return lifecycle changes in the closed
/// knowledge-time window. A fact changed twice in the window is returned once.
pub fn MemoryGraph::history(
  self : MemoryGraph,
  query : HistoryQuery,
) -> Result[Array[FactView], MemoryError] {
  match project_at_known(self, query.to_known_at) {
    Err(error) => Err(error)
    Ok(projected) => {
      let matches : Array[FactView] = []
      for stored in projected.facts {
        let activation_in_window = stored.activation_recorded_at >=
          query.from_known_at &&
          stored.activation_recorded_at <= query.to_known_at
        let closure_in_window = match stored.closure {
          Some(closure) =>
            closure.recorded_at() >= query.from_known_at &&
            closure.recorded_at() <= query.to_known_at
          None => false
        }
        if (activation_in_window || closure_in_window) &&
          history_target_matches(stored.assertion, query.target) {
          matches.push(stored_fact_view(stored))
        }
      }
      matches.sort_by(compare_fact_view)
      Ok(take_fact_views(matches, query.limit))
    }
  }
}

///|
fn fact_view_index(views : Array[FactView]) -> Map[FactId, FactView] {
  let index : Map[FactId, FactView] = Map([])
  for view in views {
    index.set(view.fact.id(), view)
  }
  index
}

///|
/// Compare visible FactIds across one changing temporal axis.
pub fn MemoryGraph::diff(
  self : MemoryGraph,
  query : DiffQuery,
) -> Result[FactDiff, MemoryError] {
  let projections : Result[(Array[FactView], Array[FactView]), MemoryError] = match
    query.axis {
    AcrossKnowledge(valid_at, from_known_at, to_known_at) =>
      match project_at_known(self, from_known_at) {
        Err(error) => Err(error)
        Ok(left_graph) =>
          match project_at_known(self, to_known_at) {
            Err(error) => Err(error)
            Ok(right_graph) =>
              Ok(
                (
                  filter_at_valid(left_graph, valid_at, query.filter),
                  filter_at_valid(right_graph, valid_at, query.filter),
                ),
              )
          }
      }
    AcrossValidity(known_at, from_valid_at, to_valid_at) =>
      match project_at_known(self, known_at) {
        Err(error) => Err(error)
        Ok(projected) =>
          Ok(
            (
              filter_at_valid(projected, from_valid_at, query.filter),
              filter_at_valid(projected, to_valid_at, query.filter),
            ),
          )
      }
  }
  let (left, right) = match projections {
    Err(error) => return Err(error)
    Ok(pair) => pair
  }
  let left_index = fact_view_index(left)
  let right_index = fact_view_index(right)
  let added : Array[FactView] = []
  let removed : Array[FactView] = []
  let unchanged : Array[FactView] = []
  for view in right {
    if left_index.contains(view.fact.id()) {
      unchanged.push(view)
    } else {
      added.push(view)
    }
  }
  for view in left {
    if !right_index.contains(view.fact.id()) {
      removed.push(view)
    }
  }
  Ok({ added, removed, unchanged })
}

///|
fn fact_visibility(stored : StoredFact, valid_at : Timestamp) -> FactVisibility {
  let fact = stored.assertion
  if valid_at < fact.valid_from() {
    return BeforeValidFrom
  }
  match fact.valid_to() {
    Some(asserted_end) if valid_at >= asserted_end =>
      match stored.closure {
        Some(closure) if closure.effective_at() < asserted_end => ()
        _ => return EndedByAssertion
      }
    _ => ()
  }
  match stored.closure {
    Some(closure) if valid_at >= closure.effective_at() =>
      match closure.cause() {
        SupersededBy(candidate, _) => EndedBySupersession(candidate)
        Retracted(_) => EndedByRetraction
      }
    _ => Visible
  }
}

///|
/// Explain one fact using only lifecycle and provenance events known at the
/// requested knowledge boundary. Facts not yet known are indistinguishable
/// from unknown identifiers.
pub fn MemoryGraph::explain(
  self : MemoryGraph,
  fact_id : FactId,
  valid_at : Timestamp,
  known_at : Timestamp,
) -> Result[ExplainReport, MemoryError] {
  let projected = match project_at_known(self, known_at) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let stored = match find_fact(projected.facts, projected.fact_index, fact_id) {
    None => return Err(MissingFact(fact_id))
    Some(value) => value
  }
  let activation_event = match
    find_event(
      projected.events,
      projected.event_index,
      stored.activation_event_id,
    ) {
    None => return Err(MissingFact(fact_id))
    Some(value) => value
  }
  let source_episodes : Array[Episode] = []
  for episode_id in stored.assertion.provenance().episode_ids() {
    match
      find_episode(projected.episodes, projected.episode_index, episode_id) {
      Some(episode) => source_episodes.push(episode)
      None => return Err(MissingEpisode(episode_id))
    }
  }
  let lifecycle_events : Array[RecordedEvent] = []
  for envelope in projected.events {
    if envelope.event_id() == stored.activation_event_id ||
      envelope.mentions_fact(fact_id) {
      lifecycle_events.push(clone_recorded_event(envelope))
    }
  }
  Ok({
    view: stored_fact_view(stored),
    valid_at,
    known_at,
    visibility: fact_visibility(stored, valid_at),
    source_episodes,
    activation_event: clone_recorded_event(activation_event),
    lifecycle_events,
  })
}
