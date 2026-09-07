// SPDX-License-Identifier: Apache-2.0

///|
/// Why a fact stopped being active.
pub(all) enum CloseReason {
  ReplacedBy(FactId)
  Retracted(String)
} derive(Eq, @debug.Debug)

///|
/// Internal lifecycle state; assertions themselves are never rewritten.
struct StoredFact {
  fact : Fact
  asserted_event : EventId
  asserted_at : Timestamp
  close_at : Timestamp?
  close_recorded_at : Timestamp?
  close_event : EventId?
  close_reason : CloseReason?
} derive(Eq)

///|
/// Small apply report used by examples and tests.
pub struct ApplyReport {
  priv accepted : Array[EventId]
  priv idempotent : Array[EventId]
}

///|
pub fn ApplyReport::accepted(self : ApplyReport) -> Array[EventId] {
  self.accepted.copy()
}

///|
pub fn ApplyReport::idempotent(self : ApplyReport) -> Array[EventId] {
  self.idempotent.copy()
}

///|
/// An in-memory event stream. Linear indexes are deliberate at this scale.
pub struct MemoryGraph {
  priv mut stream_id : String?
  priv mut last_seq : Int64?
  priv mut last_recorded_at : Timestamp?
  priv mut events : Array[RecordedEvent]
  priv mut episodes : Array[Episode]
  priv mut entities : Array[Entity]
  priv mut facts : Array[StoredFact]
}

///|
pub fn MemoryGraph::new() -> MemoryGraph {
  {
    stream_id: None,
    last_seq: None,
    last_recorded_at: None,
    events: [],
    episodes: [],
    entities: [],
    facts: [],
  }
}

///|
fn MemoryGraph::copy_state(self : MemoryGraph) -> MemoryGraph {
  {
    stream_id: self.stream_id,
    last_seq: self.last_seq,
    last_recorded_at: self.last_recorded_at,
    events: self.events.copy(),
    episodes: self.episodes.copy(),
    entities: self.entities.copy(),
    facts: self.facts.copy(),
  }
}

///|
fn MemoryGraph::event_pos(self : MemoryGraph, id : EventId) -> Int? {
  for i, item in self.events {
    if item.event_id() == id {
      return Some(i)
    }
  }
  None
}

///|
fn MemoryGraph::episode_pos(self : MemoryGraph, id : EpisodeId) -> Int? {
  for i, item in self.episodes {
    if item.id() == id {
      return Some(i)
    }
  }
  None
}

///|
fn MemoryGraph::entity_pos(self : MemoryGraph, id : EntityId) -> Int? {
  for i, item in self.entities {
    if item.id() == id {
      return Some(i)
    }
  }
  None
}

///|
fn MemoryGraph::fact_pos(self : MemoryGraph, id : FactId) -> Int? {
  for i, item in self.facts {
    if item.fact.id() == id {
      return Some(i)
    }
  }
  None
}

///|
fn MemoryGraph::validate_fact(
  self : MemoryGraph,
  fact : Fact,
) -> Result[Unit, MemoryError] {
  match self.entity_pos(fact.subject()) {
    None => return Err(MissingEntity(fact.subject()))
    Some(i) if self.entities[i].group_id() != fact.group_id() =>
      return Err(GroupConflict("fact.subject"))
    _ => ()
  }
  match fact.object() {
    EntityRef(id) =>
      match self.entity_pos(id) {
        None => return Err(MissingEntity(id))
        Some(i) if self.entities[i].group_id() != fact.group_id() =>
          return Err(GroupConflict("fact.object"))
        _ => ()
      }
    Literal(_) => ()
  }
  match self.episode_pos(fact.source_episode()) {
    None => return Err(MissingEpisode(fact.source_episode()))
    Some(i) if self.episodes[i].group_id() != fact.group_id() =>
      return Err(GroupConflict("fact.source_episode"))
    _ => ()
  }
  Ok(())
}

///|
fn MemoryGraph::insert_fact(
  self : MemoryGraph,
  fact : Fact,
  envelope : RecordedEvent,
) -> Result[Unit, MemoryError] {
  if self.fact_pos(fact.id()) is Some(_) {
    return Err(DomainConflict("fact:" + fact.id().value()))
  }
  match self.validate_fact(fact) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.facts.push({
    fact,
    asserted_event: envelope.event_id(),
    asserted_at: envelope.recorded_at(),
    close_at: None,
    close_recorded_at: None,
    close_event: None,
    close_reason: None,
  })
  Ok(())
}

///|
fn effective_end(item : StoredFact) -> Timestamp? {
  match (item.fact.valid_to(), item.close_at) {
    (None, None) => None
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (Some(a), Some(b)) => Some(if a < b { a } else { b })
  }
}

///|
fn same_slot(old : Fact, fresh : Fact) -> Bool {
  old.group_id() == fresh.group_id() &&
  old.subject() == fresh.subject() &&
  predicate_key(old.predicate()) == predicate_key(fresh.predicate()) &&
  (match (old.object(), fresh.object()) {
    (Literal(_), Literal(_)) => true
    (EntityRef(a), EntityRef(b)) => a == b
    _ => false
  })
}

///|
priv enum ApplyKind {
  Accepted
  Idempotent
}

///|
fn MemoryGraph::apply_one(
  self : MemoryGraph,
  envelope : RecordedEvent,
) -> Result[ApplyKind, MemoryError] {
  match self.event_pos(envelope.event_id()) {
    Some(i) if self.events[i] == envelope => return Ok(Idempotent)
    Some(_) => return Err(EventConflict(envelope.event_id()))
    None => ()
  }
  match self.stream_id {
    Some(expected) if expected != envelope.stream_id() =>
      return Err(StreamConflict(expected, envelope.stream_id()))
    _ => ()
  }
  match self.last_seq {
    Some(last) if envelope.seq() <= last =>
      return Err(SequenceRegression(last, envelope.seq()))
    _ => ()
  }
  match self.last_recorded_at {
    Some(last) if envelope.recorded_at() < last =>
      return Err(RecordedTimeRegression(last, envelope.recorded_at()))
    _ => ()
  }
  match envelope.payload() {
    RecordEpisode(episode) => {
      if self.episode_pos(episode.id()) is Some(_) {
        return Err(DomainConflict("episode:" + episode.id().value()))
      }
      self.episodes.push(episode)
    }
    PutEntity(entity) => {
      if self.entity_pos(entity.id()) is Some(_) {
        return Err(DomainConflict("entity:" + entity.id().value()))
      }
      self.entities.push(entity)
    }
    AssertFact(fact) =>
      match self.insert_fact(fact, envelope) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    SupersedeFact(fresh, old_ids) => {
      if old_ids.is_empty() {
        return Err(InvalidField("supersede.old_ids"))
      }
      match self.validate_fact(fresh) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      if self.fact_pos(fresh.id()) is Some(_) {
        return Err(DomainConflict("fact:" + fresh.id().value()))
      }
      for i, old_id in old_ids {
        for j in 0..<i {
          if old_ids[j] == old_id {
            return Err(SupersedeMismatch(old_id))
          }
        }
        let pos = match self.fact_pos(old_id) {
          None => return Err(MissingFact(old_id))
          Some(value) => value
        }
        let old = self.facts[pos]
        if old.close_at is Some(_) {
          return Err(FactAlreadyClosed(old_id))
        }
        if !same_slot(old.fact, fresh) ||
          fresh.valid_from() <= old.fact.valid_from() {
          return Err(SupersedeMismatch(old_id))
        }
      }
      for old_id in old_ids {
        let pos = self.fact_pos(old_id).unwrap()
        let old = self.facts[pos]
        self.facts[pos] = {
          ..old,
          close_at: Some(fresh.valid_from()),
          close_recorded_at: Some(envelope.recorded_at()),
          close_event: Some(envelope.event_id()),
          close_reason: Some(ReplacedBy(fresh.id())),
        }
      }
      match self.insert_fact(fresh, envelope) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
    RetractFact(id, at, reason) => {
      if reason.trim().is_empty() {
        return Err(InvalidField("retract.reason"))
      }
      let pos = match self.fact_pos(id) {
        None => return Err(MissingFact(id))
        Some(v) => v
      }
      let old = self.facts[pos]
      if old.close_at is Some(_) {
        return Err(FactAlreadyClosed(id))
      }
      if at <= old.fact.valid_from() {
        return Err(InvalidField("retract.at"))
      }
      self.facts[pos] = {
        ..old,
        close_at: Some(at),
        close_recorded_at: Some(envelope.recorded_at()),
        close_event: Some(envelope.event_id()),
        close_reason: Some(Retracted(reason)),
      }
    }
  }
  if self.stream_id is None {
    self.stream_id = Some(envelope.stream_id())
  }
  self.last_seq = Some(envelope.seq())
  self.last_recorded_at = Some(envelope.recorded_at())
  self.events.push(envelope)
  Ok(Accepted)
}

///|
/// Validate a whole batch on a copy, then publish it in one step.
pub fn MemoryGraph::apply(
  self : MemoryGraph,
  batch : Array[RecordedEvent],
) -> Result[ApplyReport, MemoryError] {
  let stage = self.copy_state()
  let accepted : Array[EventId] = []
  let idempotent : Array[EventId] = []
  for envelope in batch {
    match stage.apply_one(envelope) {
      Err(e) => return Err(e)
      Ok(Accepted) => accepted.push(envelope.event_id())
      Ok(Idempotent) => idempotent.push(envelope.event_id())
    }
  }
  self.stream_id = stage.stream_id
  self.last_seq = stage.last_seq
  self.last_recorded_at = stage.last_recorded_at
  self.events = stage.events
  self.episodes = stage.episodes
  self.entities = stage.entities
  self.facts = stage.facts
  Ok({ accepted, idempotent })
}

///|
/// Rebuild state from an event sequence.
pub fn MemoryGraph::replay(
  events : Array[RecordedEvent],
) -> Result[MemoryGraph, MemoryError] {
  let graph = MemoryGraph::new()
  match graph.apply(events) {
    Err(e) => Err(e)
    Ok(_) => Ok(graph)
  }
}

///|
pub fn MemoryGraph::event_count(self : MemoryGraph) -> Int {
  self.events.length()
}

///|
pub fn MemoryGraph::snapshot_events(self : MemoryGraph) -> Array[RecordedEvent] {
  self.events.copy()
}
