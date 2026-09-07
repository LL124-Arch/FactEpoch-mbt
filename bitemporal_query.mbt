// SPDX-License-Identifier: Apache-2.0

///|
/// One explicit bitemporal lookup. Structural keys are required in v0.1.
pub struct FactQuery {
  priv valid_at : Timestamp
  priv known_at : Timestamp
  priv group_id : GroupId
  priv subject : EntityId
  priv predicate : String
}

///|
pub fn FactQuery::new(
  valid_at : Timestamp,
  known_at : Timestamp,
  group_id : GroupId,
  subject : EntityId,
  predicate : String,
) -> FactQuery raise MemoryError {
  if predicate_key(predicate).is_empty() {
    raise InvalidField("query.predicate")
  }
  { valid_at, known_at, group_id, subject, predicate }
}

///|
/// Read-only view with the derived end of the fact's active interval.
pub struct FactView {
  priv fact : Fact
  priv asserted_at : Timestamp
  priv effective_valid_to : Timestamp?
  priv close_reason : CloseReason?
} derive(Eq)

///|
pub fn FactView::fact(self : FactView) -> Fact {
  self.fact
}

///|
pub fn FactView::asserted_at(self : FactView) -> Timestamp {
  self.asserted_at
}

///|
pub fn FactView::effective_valid_to(self : FactView) -> Timestamp? {
  self.effective_valid_to
}

///|
pub fn FactView::close_reason(self : FactView) -> CloseReason? {
  self.close_reason
}

///|
/// Minimal provenance report for a single known fact.
pub struct Explanation {
  priv view : FactView
  priv source : Episode
  priv assertion_event : EventId
  priv closing_event : EventId?
} derive(Eq)

///|
pub fn Explanation::view(self : Explanation) -> FactView {
  self.view
}

///|
pub fn Explanation::source(self : Explanation) -> Episode {
  self.source
}

///|
pub fn Explanation::assertion_event(self : Explanation) -> EventId {
  self.assertion_event
}

///|
pub fn Explanation::closing_event(self : Explanation) -> EventId? {
  self.closing_event
}

///|
fn view_of(item : StoredFact) -> FactView {
  {
    fact: item.fact,
    asserted_at: item.asserted_at,
    effective_valid_to: effective_end(item),
    close_reason: item.close_reason,
  }
}

///|
fn project_known(
  graph : MemoryGraph,
  known_at : Timestamp,
) -> Result[MemoryGraph, MemoryError] {
  let prefix : Array[RecordedEvent] = []
  for event in graph.events {
    if event.recorded_at() > known_at {
      break
    }
    prefix.push(event)
  }
  MemoryGraph::replay(prefix)
}

///|
fn compare_view(a : FactView, b : FactView) -> Int {
  if a.fact.confidence() > b.fact.confidence() {
    -1
  } else if a.fact.confidence() < b.fact.confidence() {
    1
  } else if a.fact.valid_from() > b.fact.valid_from() {
    -1
  } else if a.fact.valid_from() < b.fact.valid_from() {
    1
  } else {
    Compare::compare(a.fact.id(), b.fact.id())
  }
}

///|
/// Replay through `known_at`, then filter the real-world valid interval.
pub fn MemoryGraph::query(
  self : MemoryGraph,
  query : FactQuery,
) -> Result[Array[FactView], MemoryError] {
  let projected = match project_known(self, query.known_at) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let result : Array[FactView] = []
  for item in projected.facts {
    let fact = item.fact
    let before_end = match effective_end(item) {
      None => true
      Some(end) => query.valid_at < end
    }
    if fact.group_id() == query.group_id &&
      fact.subject() == query.subject &&
      predicate_key(fact.predicate()) == predicate_key(query.predicate) &&
      query.valid_at >= fact.valid_from() &&
      before_end {
      result.push(view_of(item))
    }
  }
  result.sort_by(compare_view)
  Ok(result)
}

///|
/// Return every version of a fact slot known by a given system time.
pub fn MemoryGraph::history(
  self : MemoryGraph,
  group_id : GroupId,
  subject : EntityId,
  predicate : String,
  known_at : Timestamp,
) -> Result[Array[FactView], MemoryError] {
  if predicate_key(predicate).is_empty() {
    return Err(InvalidField("history.predicate"))
  }
  let projected = match project_known(self, known_at) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let result : Array[FactView] = []
  for item in projected.facts {
    if item.fact.group_id() == group_id &&
      item.fact.subject() == subject &&
      predicate_key(item.fact.predicate()) == predicate_key(predicate) {
      result.push(view_of(item))
    }
  }
  result.sort_by((a, b) => {
    if a.fact.valid_from() < b.fact.valid_from() {
      -1
    } else if a.fact.valid_from() > b.fact.valid_from() {
      1
    } else {
      Compare::compare(a.fact.id(), b.fact.id())
    }
  })
  Ok(result)
}

///|
/// Explain the source and lifecycle visible at `known_at`.
pub fn MemoryGraph::explain(
  self : MemoryGraph,
  fact_id : FactId,
  known_at : Timestamp,
) -> Result[Explanation, MemoryError] {
  let projected = match project_known(self, known_at) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let pos = match projected.fact_pos(fact_id) {
    None => return Err(MissingFact(fact_id))
    Some(v) => v
  }
  let item = projected.facts[pos]
  let source_pos = match projected.episode_pos(item.fact.source_episode()) {
    None => return Err(MissingEpisode(item.fact.source_episode()))
    Some(v) => v
  }
  Ok({
    view: view_of(item),
    source: projected.episodes[source_pos],
    assertion_event: item.asserted_event,
    closing_event: item.close_event,
  })
}
