// SPDX-License-Identifier: Apache-2.0

///|
struct StoredFact {
  assertion : FactAssertion
  activation_event_id : EventId
  activation_recorded_at : Timestamp
  closure : FactClosure?
} derive(Eq)

///|
/// Deterministic in-memory event state for one stream.
pub struct MemoryGraph {
  priv mut stream_id : String?
  priv mut last_seq : Int64?
  priv mut last_recorded_at : Timestamp?
  priv mut events : Array[RecordedEvent]
  priv mut event_index : Map[EventId, Int]
  priv mut episodes : Array[Episode]
  priv mut episode_index : Map[EpisodeId, Int]
  priv mut entities : Array[Entity]
  priv mut entity_index : Map[EntityId, Int]
  priv mut facts : Array[StoredFact]
  priv mut fact_index : Map[FactId, Int]
}

///|
/// Construct an empty graph without reading a clock, file, or network source.
pub fn MemoryGraph::new() -> MemoryGraph {
  {
    stream_id: None,
    last_seq: None,
    last_recorded_at: None,
    events: [],
    event_index: Map([]),
    episodes: [],
    episode_index: Map([]),
    entities: [],
    entity_index: Map([]),
    facts: [],
    fact_index: Map([]),
  }
}

///|
fn find_event(
  events : Array[RecordedEvent],
  index : Map[EventId, Int],
  id : EventId,
) -> RecordedEvent? {
  match index.get(id) {
    Some(position) => Some(events[position])
    None => None
  }
}

///|
fn find_episode(
  episodes : Array[Episode],
  index : Map[EpisodeId, Int],
  id : EpisodeId,
) -> Episode? {
  match index.get(id) {
    Some(position) => Some(episodes[position])
    None => None
  }
}

///|
fn find_entity(
  entities : Array[Entity],
  index : Map[EntityId, Int],
  id : EntityId,
) -> Entity? {
  match index.get(id) {
    Some(position) => Some(entities[position])
    None => None
  }
}

///|
fn find_fact(
  facts : Array[StoredFact],
  index : Map[FactId, Int],
  id : FactId,
) -> StoredFact? {
  match index.get(id) {
    Some(position) => Some(facts[position])
    None => None
  }
}

///|
fn require_entity_in_group(
  entities : Array[Entity],
  entity_index : Map[EntityId, Int],
  id : EntityId,
  group_id : GroupId,
  reference : GroupReference,
) -> Result[Unit, MemoryError] {
  match find_entity(entities, entity_index, id) {
    None => Err(MissingEntity(id))
    Some(entity) if entity.group_id() != group_id =>
      Err(GroupMismatch(reference))
    Some(_) => Ok(())
  }
}

///|
fn validate_fact_references(
  fact : FactAssertion,
  episodes : Array[Episode],
  episode_index : Map[EpisodeId, Int],
  entities : Array[Entity],
  entity_index : Map[EntityId, Int],
) -> Result[Unit, MemoryError] {
  match
    require_entity_in_group(
      entities,
      entity_index,
      fact.subject(),
      fact.group_id(),
      SubjectReference(fact.subject()),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match fact.object() {
    EntityRef(id) =>
      match
        require_entity_in_group(
          entities,
          entity_index,
          id,
          fact.group_id(),
          ObjectReference(id),
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    Literal(_) => ()
  }
  for episode_id in fact.provenance().episode_ids() {
    match find_episode(episodes, episode_index, episode_id) {
      None => return Err(MissingEpisode(episode_id))
      Some(episode) if episode.group_id() != fact.group_id() =>
        return Err(GroupMismatch(ProvenanceReference(episode_id)))
      Some(_) => ()
    }
  }
  for evidence in fact.provenance().evidence() {
    match find_episode(episodes, episode_index, evidence.episode_id()) {
      None => return Err(MissingEpisode(evidence.episode_id()))
      Some(episode) =>
        try evidence.validate_for_body(episode.body()) catch {
          error => return Err(error)
        } noraise {
          _ => ()
        }
    }
  }
  Ok(())
}

///|
fn validate_conflict_decision(
  candidate : FactAssertion,
  old_fact_ids : Array[FactId],
  decision : ConflictDecision,
) -> Result[Unit, MemoryError] {
  if decision.action() != SupersedeExisting {
    return Err(ConflictDecisionMismatch("action"))
  }
  if decision.candidate_fact_id() != candidate.id() {
    return Err(ConflictDecisionMismatch("candidate_fact_id"))
  }
  if decision.prior_fact_ids() != old_fact_ids {
    return Err(ConflictDecisionMismatch("prior_fact_ids"))
  }
  Ok(())
}

///|
fn validate_supersession_structure(
  old_fact : FactAssertion,
  candidate : FactAssertion,
) -> Result[Unit, MemoryError] {
  if old_fact.group_id() != candidate.group_id() {
    return Err(SupersessionGuardFailed(GroupGuard))
  }
  if old_fact.subject() != candidate.subject() {
    return Err(SupersessionGuardFailed(SubjectGuard))
  }
  if predicate_key(old_fact.predicate()) != predicate_key(candidate.predicate()) {
    return Err(SupersessionGuardFailed(PredicateGuard))
  }
  match (old_fact.object(), candidate.object()) {
    (Literal(_), Literal(_)) => ()
    (EntityRef(old_endpoint), EntityRef(new_endpoint)) =>
      if old_endpoint != new_endpoint {
        return Err(SupersessionGuardFailed(DirectedEndpointGuard))
      }
    _ => return Err(SupersessionGuardFailed(ObjectKindGuard))
  }
  if !old_fact.valid_interval().overlaps(candidate.valid_interval()) {
    return Err(SupersessionGuardFailed(IntervalOverlapGuard))
  }
  Ok(())
}

///|
/// Apply an event batch atomically.
///
/// Validation and mutation happen against staged arrays. The graph publishes
/// those arrays only after every event succeeds, so callers never observe a
/// valid prefix of a rejected batch.
pub fn MemoryGraph::apply(
  self : MemoryGraph,
  batch : Array[RecordedEvent],
) -> Result[ApplyReport, MemoryError] {
  let staged_events = self.events.copy()
  let staged_event_index = self.event_index.copy()
  let staged_episodes = self.episodes.copy()
  let staged_episode_index = self.episode_index.copy()
  let staged_entities = self.entities.copy()
  let staged_entity_index = self.entity_index.copy()
  let staged_facts = self.facts.copy()
  let staged_fact_index = self.fact_index.copy()
  let mut staged_stream_id = self.stream_id
  let mut staged_last_seq = self.last_seq
  let mut staged_last_recorded_at = self.last_recorded_at
  let accepted_event_ids : Array[EventId] = []
  let idempotent_event_ids : Array[EventId] = []
  let mut created_episode_count = 0
  let mut created_entity_count = 0
  let mut created_fact_count = 0
  let mut closed_fact_count = 0
  for envelope in batch {
    match find_event(staged_events, staged_event_index, envelope.event_id()) {
      Some(existing) if existing == envelope => {
        idempotent_event_ids.push(envelope.event_id())
        continue
      }
      Some(_) => return Err(EventIdConflict(envelope.event_id()))
      None => ()
    }
    match staged_stream_id {
      Some(expected) if expected != envelope.stream_id() =>
        return Err(StreamMismatch(expected, envelope.stream_id()))
      None => staged_stream_id = Some(envelope.stream_id())
      Some(_) => ()
    }
    match staged_last_seq {
      Some(previous) if envelope.seq() <= previous =>
        return Err(SequenceNotIncreasing(previous, envelope.seq()))
      _ => ()
    }
    match staged_last_recorded_at {
      Some(previous) if envelope.recorded_at() < previous =>
        return Err(RecordedAtRegression(previous, envelope.recorded_at()))
      _ => ()
    }
    match envelope.event() {
      RecordEpisode(episode) =>
        match
          find_episode(staged_episodes, staged_episode_index, episode.id()) {
          Some(existing) if existing == episode => ()
          Some(_) => return Err(EpisodeIdConflict(episode.id()))
          None => {
            staged_episode_index.set(episode.id(), staged_episodes.length())
            staged_episodes.push(episode)
            created_episode_count += 1
          }
        }
      PutEntity(entity) =>
        match find_entity(staged_entities, staged_entity_index, entity.id()) {
          Some(existing) if existing == entity => ()
          Some(_) => return Err(EntityIdConflict(entity.id()))
          None => {
            staged_entity_index.set(entity.id(), staged_entities.length())
            staged_entities.push(entity)
            created_entity_count += 1
          }
        }
      AssertFact(fact) =>
        match find_fact(staged_facts, staged_fact_index, fact.id()) {
          Some(existing) if existing.assertion == fact => ()
          Some(_) => return Err(FactIdConflict(fact.id()))
          None => {
            match
              validate_fact_references(
                fact, staged_episodes, staged_episode_index, staged_entities, staged_entity_index,
              ) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            staged_fact_index.set(fact.id(), staged_facts.length())
            staged_facts.push({
              assertion: fact,
              activation_event_id: envelope.event_id(),
              activation_recorded_at: envelope.recorded_at(),
              closure: None,
            })
            created_fact_count += 1
          }
        }
      SupersedeFact(candidate, old_fact_ids, decision) => {
        match validate_conflict_decision(candidate, old_fact_ids, decision) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match find_fact(staged_facts, staged_fact_index, candidate.id()) {
          Some(existing) if existing.assertion != candidate =>
            return Err(FactIdConflict(candidate.id()))
          Some(existing) if existing.closure is Some(_) =>
            return Err(FactAlreadyClosed(candidate.id()))
          _ => ()
        }
        match
          validate_fact_references(
            candidate, staged_episodes, staged_episode_index, staged_entities, staged_entity_index,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        for old_fact_id in old_fact_ids {
          match find_fact(staged_facts, staged_fact_index, old_fact_id) {
            None => return Err(MissingFact(old_fact_id))
            Some(existing) if existing.closure is Some(_) =>
              return Err(FactAlreadyClosed(old_fact_id))
            Some(existing) =>
              match
                validate_supersession_structure(existing.assertion, candidate) {
                Err(error) => return Err(error)
                Ok(_) => ()
              }
          }
        }
        if find_fact(staged_facts, staged_fact_index, candidate.id()) is None {
          staged_fact_index.set(candidate.id(), staged_facts.length())
          staged_facts.push({
            assertion: candidate,
            activation_event_id: envelope.event_id(),
            activation_recorded_at: envelope.recorded_at(),
            closure: None,
          })
          created_fact_count += 1
        }
        for old_fact_id in old_fact_ids {
          let position = staged_fact_index[old_fact_id]
          let existing = staged_facts[position]
          staged_facts[position] = {
            assertion: existing.assertion,
            activation_event_id: existing.activation_event_id,
            activation_recorded_at: existing.activation_recorded_at,
            closure: Some(
              FactClosure::make(
                envelope.event_id(),
                envelope.recorded_at(),
                candidate.valid_from(),
                SupersededBy(candidate.id(), decision),
              ),
            ),
          }
          closed_fact_count += 1
        }
      }
      RetractFact(fact_id, effective_at, reason) =>
        match find_fact(staged_facts, staged_fact_index, fact_id) {
          None => return Err(MissingFact(fact_id))
          Some(existing) if existing.closure is Some(_) =>
            return Err(FactAlreadyClosed(fact_id))
          Some(existing) => {
            let position = staged_fact_index[fact_id]
            staged_facts[position] = {
              assertion: existing.assertion,
              activation_event_id: existing.activation_event_id,
              activation_recorded_at: existing.activation_recorded_at,
              closure: Some(
                FactClosure::make(
                  envelope.event_id(),
                  envelope.recorded_at(),
                  effective_at,
                  Retracted(reason),
                ),
              ),
            }
            closed_fact_count += 1
          }
        }
    }
    staged_event_index.set(envelope.event_id(), staged_events.length())
    staged_events.push(envelope)
    accepted_event_ids.push(envelope.event_id())
    staged_last_seq = Some(envelope.seq())
    staged_last_recorded_at = Some(envelope.recorded_at())
  }
  self.stream_id = staged_stream_id
  self.last_seq = staged_last_seq
  self.last_recorded_at = staged_last_recorded_at
  self.events = staged_events
  self.event_index = staged_event_index
  self.episodes = staged_episodes
  self.episode_index = staged_episode_index
  self.entities = staged_entities
  self.entity_index = staged_entity_index
  self.facts = staged_facts
  self.fact_index = staged_fact_index
  Ok(
    ApplyReport::make(
      accepted_event_ids,
      idempotent_event_ids,
      created_episode_count,
      created_entity_count,
      created_fact_count,
      closed_fact_count,
      self.events.length(),
    ),
  )
}

///|
/// Rebuild a graph using the same atomic validation path as live ingestion.
pub fn MemoryGraph::replay(
  events : Array[RecordedEvent],
) -> Result[MemoryGraph, MemoryError] {
  let graph = MemoryGraph::new()
  match graph.apply(events) {
    Ok(_) => Ok(graph)
    Err(error) => Err(error)
  }
}

///|
/// Return accepted events in stream order as a defensive array.
pub fn MemoryGraph::snapshot_events(self : MemoryGraph) -> Array[RecordedEvent] {
  self.events.map(clone_recorded_event)
}
