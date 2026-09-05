// SPDX-License-Identifier: Apache-2.0

///|
/// A deterministic mutation accepted by the in-memory graph.
///
/// Supersession, retraction, and forgetting are intentionally introduced by
/// later milestones instead of being implied by an assertion.
pub(all) enum MemoryEvent {
  RecordEpisode(Episode)
  PutEntity(Entity)
  AssertFact(FactAssertion)
} derive(Eq)

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
  { stream_id, seq, event_id, recorded_at, event }
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
  self.event
}
