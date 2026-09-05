// SPDX-License-Identifier: Apache-2.0

///|
/// Counts and event identities produced by one atomic apply operation.
///
/// A semantic digest is deliberately absent until canonical encoding and the
/// integrity package define what bytes that digest covers.
pub struct ApplyReport {
  priv accepted_event_ids : Array[EventId]
  priv idempotent_event_ids : Array[EventId]
  priv created_episode_count : Int
  priv created_entity_count : Int
  priv created_fact_count : Int
  priv event_count : Int
}

///|
fn ApplyReport::make(
  accepted_event_ids : Array[EventId],
  idempotent_event_ids : Array[EventId],
  created_episode_count : Int,
  created_entity_count : Int,
  created_fact_count : Int,
  event_count : Int,
) -> ApplyReport {
  {
    accepted_event_ids,
    idempotent_event_ids,
    created_episode_count,
    created_entity_count,
    created_fact_count,
    event_count,
  }
}

///|
/// Return newly accepted event IDs in input order.
pub fn ApplyReport::accepted_event_ids(self : ApplyReport) -> Array[EventId] {
  self.accepted_event_ids.copy()
}

///|
/// Return exact duplicate event IDs in input order.
pub fn ApplyReport::idempotent_event_ids(self : ApplyReport) -> Array[EventId] {
  self.idempotent_event_ids.copy()
}

///|
pub fn ApplyReport::created_episode_count(self : ApplyReport) -> Int {
  self.created_episode_count
}

///|
pub fn ApplyReport::created_entity_count(self : ApplyReport) -> Int {
  self.created_entity_count
}

///|
pub fn ApplyReport::created_fact_count(self : ApplyReport) -> Int {
  self.created_fact_count
}

///|
/// Return the graph's total accepted event count after this operation.
pub fn ApplyReport::event_count(self : ApplyReport) -> Int {
  self.event_count
}
