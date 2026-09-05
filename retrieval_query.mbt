// SPDX-License-Identifier: Apache-2.0

///|
/// A fused score joined to a temporally visible fact.
pub struct RankedFactView {
  priv view : FactView
  priv score : Double
  priv contributions : Array[RankContribution]
} derive(Eq)

///|
pub fn RankedFactView::view(self : RankedFactView) -> FactView {
  self.view
}

///|
pub fn RankedFactView::score(self : RankedFactView) -> Double {
  self.score
}

///|
pub fn RankedFactView::contributions(
  self : RankedFactView,
) -> Array[RankContribution] {
  self.contributions.copy()
}

///|
fn compare_ranked_fact_view(
  left : RankedFactView,
  right : RankedFactView,
) -> Int {
  if left.score > right.score {
    -1
  } else if left.score < right.score {
    1
  } else if left.view.fact.valid_from() > right.view.fact.valid_from() {
    -1
  } else if left.view.fact.valid_from() < right.view.fact.valid_from() {
    1
  } else if left.view.fact.id() < right.view.fact.id() {
    -1
  } else if left.view.fact.id() > right.view.fact.id() {
    1
  } else {
    0
  }
}

///|
/// Join caller-ranked FactIds with an unbounded bitemporal visibility
/// projection, then apply only the requested output limit.
pub fn MemoryGraph::query_ranked(
  self : MemoryGraph,
  query : FactQuery,
  fused : Array[FusedCandidate],
) -> Result[Array[RankedFactView], MemoryError] {
  let fused_index : Map[FactId, FusedCandidate] = Map([])
  for candidate in fused {
    if fused_index.contains(candidate.fact_id) {
      return Err(DuplicateFusedCandidate(candidate.fact_id))
    }
    fused_index.set(candidate.fact_id, candidate)
  }
  let projected = match project_at_known(self, query.known_at) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let visible = filter_at_valid(projected, query.valid_at, query.filter)
  let ranked : Array[RankedFactView] = []
  for view in visible {
    match fused_index.get(view.fact.id()) {
      None => ()
      Some(candidate) =>
        ranked.push({
          view,
          score: candidate.score,
          contributions: candidate.contributions.copy(),
        })
    }
  }
  ranked.sort_by(compare_ranked_fact_view)
  Ok(take_fact_views_ranked(ranked, query.limit))
}

///|
fn take_fact_views_ranked(
  views : Array[RankedFactView],
  limit : Int,
) -> Array[RankedFactView] {
  if views.length() <= limit {
    views
  } else {
    let limited : Array[RankedFactView] = []
    for index in 0..<limit {
      limited.push(views[index])
    }
    limited
  }
}

///|
pub(all) enum NeighborDirection {
  Outgoing
  Incoming
  Both
} derive(Eq)

///|
pub struct NeighborQuery {
  priv start : EntityId
  priv valid_at : Timestamp
  priv known_at : Timestamp
  priv max_depth : Int
  priv direction : NeighborDirection
  priv group_id : GroupId?
  priv predicate_key : String?
  priv limit : Int
}

///|
pub fn NeighborQuery::new(
  start : EntityId,
  valid_at : Timestamp,
  known_at : Timestamp,
  max_depth : Int,
  direction : NeighborDirection,
  group_id? : GroupId,
  predicate? : String,
  limit? : Int = 100,
) -> NeighborQuery raise MemoryError {
  if max_depth < 0 || max_depth > 64 {
    raise InvalidNeighborDepth(max_depth)
  }
  if limit < 1 || limit > 10_000 {
    raise InvalidLimit(limit)
  }
  let normalized_predicate = match predicate {
    None => None
    Some(value) => {
      let key = predicate_key(value)
      if key.is_empty() {
        raise InvalidField("predicate", "must not normalize to empty")
      }
      Some(key)
    }
  }
  {
    start,
    valid_at,
    known_at,
    max_depth,
    direction,
    group_id,
    predicate_key: normalized_predicate,
    limit,
  }
}

///|
pub fn NeighborQuery::start(self : NeighborQuery) -> EntityId {
  self.start
}

///|
pub fn NeighborQuery::valid_at(self : NeighborQuery) -> Timestamp {
  self.valid_at
}

///|
pub fn NeighborQuery::known_at(self : NeighborQuery) -> Timestamp {
  self.known_at
}

///|
pub fn NeighborQuery::max_depth(self : NeighborQuery) -> Int {
  self.max_depth
}

///|
pub fn NeighborQuery::direction(self : NeighborQuery) -> NeighborDirection {
  self.direction
}

///|
pub fn NeighborQuery::group_id(self : NeighborQuery) -> GroupId? {
  self.group_id
}

///|
pub fn NeighborQuery::predicate_key(self : NeighborQuery) -> String? {
  self.predicate_key
}

///|
pub fn NeighborQuery::limit(self : NeighborQuery) -> Int {
  self.limit
}

///|
pub struct NeighborView {
  priv view : FactView
  priv depth : Int
} derive(Eq)

///|
pub fn NeighborView::view(self : NeighborView) -> FactView {
  self.view
}

///|
pub fn NeighborView::depth(self : NeighborView) -> Int {
  self.depth
}

///|
fn neighbor_fact_matches(fact : FactAssertion, query : NeighborQuery) -> Bool {
  match query.group_id {
    Some(group_id) if fact.group_id() != group_id => return false
    _ => ()
  }
  match query.predicate_key {
    Some(key) if predicate_key(fact.predicate()) != key => return false
    _ => ()
  }
  true
}

///|
fn compare_neighbor_layer(left : FactView, right : FactView) -> Int {
  compare_fact_view(left, right)
}

///|
/// Traverse visible facts in deterministic breadth-first layers.
pub fn MemoryGraph::neighbors(
  self : MemoryGraph,
  query : NeighborQuery,
) -> Result[Array[NeighborView], MemoryError] {
  let projected = match project_at_known(self, query.known_at) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if find_entity(projected.entities, projected.entity_index, query.start)
    is None {
    return Err(MissingEntity(query.start))
  }
  if query.max_depth == 0 {
    return Ok([])
  }
  let all_visible = filter_at_valid(
    projected,
    query.valid_at,
    FactFilter::all(),
  )
  let visible : Array[FactView] = []
  for view in all_visible {
    if neighbor_fact_matches(view.fact, query) {
      visible.push(view)
    }
  }
  let visited_entities : Map[EntityId, Bool] = Map([])
  let visited_facts : Map[FactId, Bool] = Map([])
  visited_entities.set(query.start, true)
  let mut frontier : Array[EntityId] = [query.start]
  let mut frontier_set : Map[EntityId, Bool] = Map([(query.start, true)])
  let output : Array[NeighborView] = []
  for depth in 1..<=query.max_depth {
    if frontier.is_empty() {
      break
    }
    let next_frontier : Array[EntityId] = []
    let layer : Array[FactView] = []
    for view in visible {
      let fact = view.fact
      let mut reached = false
      match fact.object() {
        Literal(_) =>
          if query.direction != Incoming &&
            frontier_set.contains(fact.subject()) {
            reached = true
          }
        EntityRef(object_id) => {
          if query.direction != Incoming &&
            frontier_set.contains(fact.subject()) {
            reached = true
            if !visited_entities.contains(object_id) {
              visited_entities.set(object_id, true)
              next_frontier.push(object_id)
            }
          }
          if query.direction != Outgoing && frontier_set.contains(object_id) {
            reached = true
            if !visited_entities.contains(fact.subject()) {
              visited_entities.set(fact.subject(), true)
              next_frontier.push(fact.subject())
            }
          }
        }
      }
      if reached && !visited_facts.contains(fact.id()) {
        visited_facts.set(fact.id(), true)
        layer.push(view)
      }
    }
    layer.sort_by(compare_neighbor_layer)
    for view in layer {
      if output.length() == query.limit {
        return Ok(output)
      }
      output.push({ view, depth })
    }
    next_frontier.sort()
    frontier = next_frontier
    frontier_set = Map([])
    for entity_id in frontier {
      frontier_set.set(entity_id, true)
    }
  }
  Ok(output)
}
