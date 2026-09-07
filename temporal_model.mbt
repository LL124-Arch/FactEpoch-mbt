// SPDX-License-Identifier: Apache-2.0

///|
/// Errors kept small enough for callers to handle without parsing messages.
pub(all) suberror MemoryError {
  InvalidId(String)
  InvalidField(String)
  InvalidInterval(Timestamp, Timestamp)
  InvalidSequence(Int64)
  EventConflict(EventId)
  StreamConflict(String, String)
  SequenceRegression(Int64, Int64)
  RecordedTimeRegression(Timestamp, Timestamp)
  DomainConflict(String)
  MissingEpisode(EpisodeId)
  MissingEntity(EntityId)
  MissingFact(FactId)
  GroupConflict(String)
  FactAlreadyClosed(FactId)
  SupersedeMismatch(FactId)
} derive(Eq, @debug.Debug)

///|
/// Caller-owned IDs. FactEpoch validates but never invents them.
pub struct EventId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
pub struct EpisodeId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
pub struct EntityId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
pub struct FactId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
pub struct GroupId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
fn checked_id(value : String) -> String raise MemoryError {
  if value.trim().is_empty() {
    raise InvalidId(value)
  }
  value
}

///|
pub fn EventId::new(value : String) -> EventId raise MemoryError {
  { value: checked_id(value) }
}

///|
pub fn EpisodeId::new(value : String) -> EpisodeId raise MemoryError {
  { value: checked_id(value) }
}

///|
pub fn EntityId::new(value : String) -> EntityId raise MemoryError {
  { value: checked_id(value) }
}

///|
pub fn FactId::new(value : String) -> FactId raise MemoryError {
  { value: checked_id(value) }
}

///|
pub fn GroupId::new(value : String) -> GroupId raise MemoryError {
  { value: checked_id(value) }
}

///|
pub fn EventId::value(self : EventId) -> String {
  self.value
}

///|
pub fn EpisodeId::value(self : EpisodeId) -> String {
  self.value
}

///|
pub fn EntityId::value(self : EntityId) -> String {
  self.value
}

///|
pub fn FactId::value(self : FactId) -> String {
  self.value
}

///|
pub fn GroupId::value(self : GroupId) -> String {
  self.value
}

///|
/// UTC milliseconds. The portable core never reads a clock.
pub struct Timestamp {
  priv millis : Int64
} derive(Eq, Compare, Hash, @debug.Debug)

///|
pub fn Timestamp::from_unix_millis(millis : Int64) -> Timestamp {
  { millis, }
}

///|
pub fn Timestamp::to_unix_millis(self : Timestamp) -> Int64 {
  self.millis
}

///|
/// A half-open valid-time interval: `[from, to)`.
pub struct ValidInterval {
  priv from : Timestamp
  priv to : Timestamp?
} derive(Eq, @debug.Debug)

///|
pub fn ValidInterval::new(
  from : Timestamp,
  to : Timestamp?,
) -> ValidInterval raise MemoryError {
  match to {
    Some(bound) if bound <= from => raise InvalidInterval(from, bound)
    _ => { from, to }
  }
}

///|
pub fn ValidInterval::from(self : ValidInterval) -> Timestamp {
  self.from
}

///|
pub fn ValidInterval::to(self : ValidInterval) -> Timestamp? {
  self.to
}

///|
pub fn ValidInterval::contains(self : ValidInterval, at : Timestamp) -> Bool {
  at >= self.from &&
  (match self.to {
    Some(bound) => at < bound
    None => true
  })
}

///|
/// Normalize only the ASCII spelling used for matching slots.
fn predicate_key(value : String) -> String {
  let out = StringBuilder()
  let mut pending_space = false
  let mut wrote = false
  for ch in value {
    let n = ch.to_int()
    let whitespace = n == 0x20 || (n >= 0x09 && n <= 0x0d)
    if whitespace {
      if wrote {
        pending_space = true
      }
    } else {
      if pending_space {
        out.write_char(' ')
        pending_space = false
      }
      if n >= 0x41 && n <= 0x5a {
        match (n + 0x20).to_char() {
          Some(lower) => out.write_char(lower)
          None => abort("ASCII conversion failed")
        }
      } else {
        out.write_char(ch)
      }
      wrote = true
    }
  }
  out.to_string()
}

///|
/// One source episode. Text stays intact so an explanation can cite it.
pub struct Episode {
  priv id : EpisodeId
  priv group_id : GroupId
  priv text : String
  priv source : String?
} derive(Eq, @debug.Debug)

///|
pub fn Episode::new(
  id : EpisodeId,
  group_id : GroupId,
  text : String,
  source? : String,
) -> Episode raise MemoryError {
  if text.trim().is_empty() {
    raise InvalidField("episode.text")
  }
  match source {
    Some(s) if s.trim().is_empty() => raise InvalidField("episode.source")
    _ => ()
  }
  { id, group_id, text, source }
}

///|
pub fn Episode::id(self : Episode) -> EpisodeId {
  self.id
}

///|
pub fn Episode::group_id(self : Episode) -> GroupId {
  self.group_id
}

///|
pub fn Episode::text(self : Episode) -> String {
  self.text
}

///|
pub fn Episode::source(self : Episode) -> String? {
  self.source
}

///|
/// A graph node intentionally has only the fields needed by the prototype.
pub struct Entity {
  priv id : EntityId
  priv group_id : GroupId
  priv name : String
} derive(Eq, @debug.Debug)

///|
pub fn Entity::new(
  id : EntityId,
  group_id : GroupId,
  name : String,
) -> Entity raise MemoryError {
  if name.trim().is_empty() {
    raise InvalidField("entity.name")
  }
  { id, group_id, name }
}

///|
pub fn Entity::id(self : Entity) -> EntityId {
  self.id
}

///|
pub fn Entity::group_id(self : Entity) -> GroupId {
  self.group_id
}

///|
pub fn Entity::name(self : Entity) -> String {
  self.name
}

///|
/// Facts can point to another entity or to a plain value.
pub(all) enum FactObject {
  EntityRef(EntityId)
  Literal(String)
} derive(Eq, Compare, @debug.Debug)

///|
/// An immutable assertion with one explicit source episode.
pub struct Fact {
  priv id : FactId
  priv group_id : GroupId
  priv subject : EntityId
  priv predicate : String
  priv object : FactObject
  priv statement : String
  priv interval : ValidInterval
  priv source_episode : EpisodeId
  priv confidence : Int
} derive(Eq, @debug.Debug)

///|
pub fn Fact::new(
  id : FactId,
  group_id : GroupId,
  subject : EntityId,
  predicate : String,
  object : FactObject,
  statement : String,
  valid_from : Timestamp,
  valid_to? : Timestamp,
  source_episode : EpisodeId,
  confidence? : Int = 100,
) -> Fact raise MemoryError {
  if predicate_key(predicate).is_empty() {
    raise InvalidField("fact.predicate")
  }
  if statement.trim().is_empty() {
    raise InvalidField("fact.statement")
  }
  match object {
    Literal(v) if v.trim().is_empty() => raise InvalidField("fact.literal")
    _ => ()
  }
  if confidence < 0 || confidence > 100 {
    raise InvalidField("fact.confidence")
  }
  {
    id,
    group_id,
    subject,
    predicate,
    object,
    statement,
    interval: ValidInterval::new(valid_from, valid_to),
    source_episode,
    confidence,
  }
}

///|
pub fn Fact::id(self : Fact) -> FactId {
  self.id
}

///|
pub fn Fact::group_id(self : Fact) -> GroupId {
  self.group_id
}

///|
pub fn Fact::subject(self : Fact) -> EntityId {
  self.subject
}

///|
pub fn Fact::predicate(self : Fact) -> String {
  self.predicate
}

///|
pub fn Fact::object(self : Fact) -> FactObject {
  self.object
}

///|
pub fn Fact::statement(self : Fact) -> String {
  self.statement
}

///|
pub fn Fact::valid_from(self : Fact) -> Timestamp {
  self.interval.from()
}

///|
pub fn Fact::valid_to(self : Fact) -> Timestamp? {
  self.interval.to()
}

///|
pub fn Fact::source_episode(self : Fact) -> EpisodeId {
  self.source_episode
}

///|
pub fn Fact::confidence(self : Fact) -> Int {
  self.confidence
}

///|
/// Every state change is explicit; replacement never comes from a query.
pub(all) enum MemoryEvent {
  RecordEpisode(Episode)
  PutEntity(Entity)
  AssertFact(Fact)
  SupersedeFact(Fact, Array[FactId])
  RetractFact(FactId, Timestamp, String)
} derive(Eq, @debug.Debug)

///|
/// Caller-stamped envelope used for deterministic replay.
pub struct RecordedEvent {
  priv stream_id : String
  priv seq : Int64
  priv event_id : EventId
  priv recorded_at : Timestamp
  priv event : MemoryEvent
} derive(Eq, @debug.Debug)

///|
pub fn RecordedEvent::new(
  stream_id : String,
  seq : Int64,
  event_id : EventId,
  recorded_at : Timestamp,
  event : MemoryEvent,
) -> RecordedEvent raise MemoryError {
  if stream_id.trim().is_empty() {
    raise InvalidField("event.stream_id")
  }
  if seq <= 0L {
    raise InvalidSequence(seq)
  }
  let stable_event = match event {
    SupersedeFact(fact, ids) => SupersedeFact(fact, ids.copy())
    other => other
  }
  { stream_id, seq, event_id, recorded_at, event: stable_event }
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
fn RecordedEvent::payload(self : RecordedEvent) -> MemoryEvent {
  self.event
}
