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
  {
    fact,
    predicate_key: predicate_key(fact.predicate()),
    activation_event_id: stored.activation_event_id,
    activation_recorded_at: stored.activation_recorded_at,
    effective_valid_to: fact.valid_to(),
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
    if stored.assertion.valid_interval().contains(valid_at) &&
      fact_matches_filter(stored.assertion, filter) {
      visible.push(stored_fact_view(stored))
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
/// Replay through the upper bound, then return activations in the closed window.
/// Closure transitions join this history in the conflict milestone.
pub fn MemoryGraph::history(
  self : MemoryGraph,
  query : HistoryQuery,
) -> Result[Array[FactView], MemoryError] {
  match project_at_known(self, query.to_known_at) {
    Err(error) => Err(error)
    Ok(projected) => {
      let matches : Array[FactView] = []
      for stored in projected.facts {
        if stored.activation_recorded_at >= query.from_known_at &&
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
