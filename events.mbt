// SPDX-License-Identifier: Apache-2.0

///|
/// A deterministic mutation accepted by the in-memory graph.
///
/// Supersession and retraction are explicit terminal lifecycle changes;
/// forgetting is introduced by a later milestone.
pub(all) enum MemoryEvent {
  RecordEpisode(Episode)
  PutEntity(Entity)
  AssertFact(FactAssertion)
  SupersedeFact(FactAssertion, Array[FactId], ConflictDecision)
  RetractFact(FactId, Timestamp, String)
} derive(Eq)

///|
fn normalize_memory_event(event : MemoryEvent) -> MemoryEvent raise MemoryError {
  match event {
    RecordEpisode(episode) => RecordEpisode(episode)
    PutEntity(entity) => PutEntity(entity)
    AssertFact(fact) => AssertFact(fact)
    SupersedeFact(candidate, old_fact_ids, decision) => {
      let normalized = normalized_fact_id_set(old_fact_ids, "old_fact_ids")
      if normalized.contains(candidate.id()) {
        raise ConflictDecisionMismatch("candidate_in_old_fact_ids")
      }
      SupersedeFact(candidate, normalized, decision)
    }
    RetractFact(fact_id, effective_at, reason) => {
      require_nonempty("reason", reason)
      RetractFact(fact_id, effective_at, reason)
    }
  }
}

///|
fn clone_memory_event(event : MemoryEvent) -> MemoryEvent {
  match event {
    RecordEpisode(episode) => RecordEpisode(episode)
    PutEntity(entity) => PutEntity(entity)
    AssertFact(fact) => AssertFact(fact)
    SupersedeFact(candidate, old_fact_ids, decision) =>
      SupersedeFact(candidate, old_fact_ids.copy(), decision)
    RetractFact(fact_id, effective_at, reason) =>
      RetractFact(fact_id, effective_at, reason)
  }
}

///|
/// A caller-stamped event in stream order.
pub struct RecordedEvent {
  priv stream_id : String
  priv seq : Int64
  priv event_id : EventId
  priv recorded_at : Timestamp
  priv event : MemoryEvent
} derive(Eq)

///|
/// Construct an event envelope without reading a clock or allocating an ID.
pub fn RecordedEvent::new(
  stream_id : String,
  seq : Int64,
  event_id : EventId,
  recorded_at : Timestamp,
  event : MemoryEvent,
) -> RecordedEvent raise MemoryError {
  require_nonempty("stream_id", stream_id)
  if seq <= 0L {
    raise InvalidSequence(seq)
  }
  {
    stream_id,
    seq,
    event_id,
    recorded_at,
    event: normalize_memory_event(event),
  }
}

///|
pub fn RecordedEvent::stream_id(self : RecordedEvent) -> String {
  self.stream_id
}

///|
pub fn RecordedEvent::seq(self : RecordedEvent) -> Int64 {
  self.seq
}

///|
pub fn RecordedEvent::event_id(self : RecordedEvent) -> EventId {
  self.event_id
}

///|
pub fn RecordedEvent::recorded_at(self : RecordedEvent) -> Timestamp {
  self.recorded_at
}

///|
pub fn RecordedEvent::event(self : RecordedEvent) -> MemoryEvent {
  clone_memory_event(self.event)
}

///|
fn clone_recorded_event(event : RecordedEvent) -> RecordedEvent {
  {
    stream_id: event.stream_id,
    seq: event.seq,
    event_id: event.event_id,
    recorded_at: event.recorded_at,
    event: clone_memory_event(event.event),
  }
}

///|
/// Match explicit lifecycle participation without exposing or copying payload.
/// First activation is checked separately because repeated equal assertions are
/// semantic no-ops rather than lifecycle changes.
fn RecordedEvent::mentions_fact(self : RecordedEvent, fact_id : FactId) -> Bool {
  match self.event {
    SupersedeFact(candidate, old_fact_ids, _) =>
      candidate.id() == fact_id || old_fact_ids.contains(fact_id)
    RetractFact(target, _, _) => target == fact_id
    _ => false
  }
}
