// SPDX-License-Identifier: Apache-2.0

///|
fn require_nonempty(field : String, value : String) -> Unit raise MemoryError {
  if value.is_empty() {
    raise InvalidField(field, "must not be empty")
  }
}

///|
fn predicate_key(predicate : String) -> String {
  let normalized = StringBuilder()
  let mut has_output = false
  let mut pending_space = false
  for char in predicate {
    let code = char.to_int()
    let ascii_whitespace = code == 0x20 || (code >= 0x09 && code <= 0x0d)
    if ascii_whitespace {
      if has_output {
        pending_space = true
      }
    } else {
      if pending_space {
        normalized.write_char(' ')
        pending_space = false
      }
      if code >= 0x41 && code <= 0x5a {
        match (code + 0x20).to_char() {
          Some(lowercase) => normalized.write_char(lowercase)
          None => abort("ASCII lowercase conversion must be valid")
        }
      } else {
        normalized.write_char(char)
      }
      has_output = true
    }
  }
  normalized.to_string()
}

///|
/// Source material that may support one or more facts.
pub struct Episode {
  priv id : EpisodeId
  priv group_id : GroupId
  priv body : String
  priv source_uri : String?
  priv occurred_from : Timestamp?
  priv occurred_to : Timestamp?
  priv metadata : Metadata
} derive(Eq)

///|
/// Construct and validate an episode.
pub fn Episode::new(
  id : EpisodeId,
  group_id : GroupId,
  body : String,
  source_uri : String?,
  occurred_from : Timestamp?,
  occurred_to : Timestamp?,
  metadata : Metadata,
) -> Episode raise MemoryError {
  require_nonempty("body", body)
  match source_uri {
    Some(value) => require_nonempty("source_uri", value)
    None => ()
  }
  match (occurred_from, occurred_to) {
    (Some(start), end) => ignore(ValidInterval::new(start, end))
    (None, Some(_)) =>
      raise InvalidField("occurred_to", "requires occurred_from")
    (None, None) => ()
  }
  { id, group_id, body, source_uri, occurred_from, occurred_to, metadata }
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
pub fn Episode::body(self : Episode) -> String {
  self.body
}

///|
pub fn Episode::source_uri(self : Episode) -> String? {
  self.source_uri
}

///|
pub fn Episode::occurred_from(self : Episode) -> Timestamp? {
  self.occurred_from
}

///|
pub fn Episode::occurred_to(self : Episode) -> Timestamp? {
  self.occurred_to
}

///|
pub fn Episode::metadata(self : Episode) -> Metadata {
  self.metadata
}

///|
/// A named node in a fact graph.
pub struct Entity {
  priv id : EntityId
  priv group_id : GroupId
  priv name : String
  priv kind : String
  priv summary : String?
  priv metadata : Metadata
} derive(Eq)

///|
/// Construct and validate an entity.
pub fn Entity::new(
  id : EntityId,
  group_id : GroupId,
  name : String,
  kind : String,
  summary : String?,
  metadata : Metadata,
) -> Entity raise MemoryError {
  require_nonempty("name", name)
  require_nonempty("kind", kind)
  { id, group_id, name, kind, summary, metadata }
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
pub fn Entity::kind(self : Entity) -> String {
  self.kind
}

///|
pub fn Entity::summary(self : Entity) -> String? {
  self.summary
}

///|
pub fn Entity::metadata(self : Entity) -> Metadata {
  self.metadata
}

///|
/// The object of a directed fact assertion.
pub(all) enum FactObject {
  EntityRef(EntityId)
  Literal(String)
} derive(Eq, Compare)

///|
/// A validated fact and its valid-time interval.
pub struct FactAssertion {
  priv id : FactId
  priv group_id : GroupId
  priv subject : EntityId
  priv predicate : String
  priv object : FactObject
  priv statement : String
  priv valid_interval : ValidInterval
  priv confidence_basis_points : Int
  priv provenance : Provenance
} derive(Eq)

///|
/// Construct a fact. Referential group checks occur when an event is applied.
pub fn FactAssertion::new(
  id : FactId,
  group_id : GroupId,
  subject : EntityId,
  predicate : String,
  object : FactObject,
  statement : String,
  valid_from : Timestamp,
  valid_to : Timestamp?,
  confidence_basis_points : Int,
  provenance : Provenance,
) -> FactAssertion raise MemoryError {
  if predicate_key(predicate).is_empty() {
    raise InvalidField("predicate", "must not normalize to empty")
  }
  require_nonempty("statement", statement)
  match object {
    Literal(value) => require_nonempty("object.literal", value)
    EntityRef(_) => ()
  }
  if confidence_basis_points < 0 || confidence_basis_points > 10_000 {
    raise InvalidConfidence(confidence_basis_points)
  }
  let valid_interval = ValidInterval::new(valid_from, valid_to)
  {
    id,
    group_id,
    subject,
    predicate,
    object,
    statement,
    valid_interval,
    confidence_basis_points,
    provenance,
  }
}

///|
pub fn FactAssertion::id(self : FactAssertion) -> FactId {
  self.id
}

///|
pub fn FactAssertion::group_id(self : FactAssertion) -> GroupId {
  self.group_id
}

///|
pub fn FactAssertion::subject(self : FactAssertion) -> EntityId {
  self.subject
}

///|
pub fn FactAssertion::predicate(self : FactAssertion) -> String {
  self.predicate
}

///|
pub fn FactAssertion::object(self : FactAssertion) -> FactObject {
  self.object
}

///|
pub fn FactAssertion::statement(self : FactAssertion) -> String {
  self.statement
}

///|
pub fn FactAssertion::valid_interval(self : FactAssertion) -> ValidInterval {
  self.valid_interval
}

///|
pub fn FactAssertion::valid_from(self : FactAssertion) -> Timestamp {
  self.valid_interval.start()
}

///|
pub fn FactAssertion::valid_to(self : FactAssertion) -> Timestamp? {
  self.valid_interval.end()
}

///|
pub fn FactAssertion::confidence_basis_points(self : FactAssertion) -> Int {
  self.confidence_basis_points
}

///|
pub fn FactAssertion::provenance(self : FactAssertion) -> Provenance {
  self.provenance
}
