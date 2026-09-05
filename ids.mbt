// SPDX-License-Identifier: Apache-2.0

///|
let max_identifier_utf8_bytes = 255

///|
fn checked_identifier(
  kind : String,
  value : String,
) -> String raise MemoryError {
  if value.is_empty() {
    raise InvalidIdentifier(kind, "must not be empty")
  }
  let byte_length = @utf8.encode(value, bom=false).length()
  if byte_length > max_identifier_utf8_bytes {
    raise InvalidIdentifier(
      kind, "must be at most 255 bytes when encoded as UTF-8",
    )
  }
  value
}

///|
/// An opaque caller-supplied event identifier.
pub struct EventId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct an event identifier.
pub fn EventId::new(value : String) -> EventId raise MemoryError {
  { value: checked_identifier("EventId", value) }
}

///|
/// Return the immutable textual value.
pub fn EventId::value(self : EventId) -> String {
  self.value
}

///|
/// An opaque identifier for an extraction candidate before fact allocation.
pub struct CandidateId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct a candidate identifier.
pub fn CandidateId::new(value : String) -> CandidateId raise MemoryError {
  { value: checked_identifier("CandidateId", value) }
}

///|
/// Return the immutable textual value.
pub fn CandidateId::value(self : CandidateId) -> String {
  self.value
}

///|
/// An opaque caller-supplied episode identifier.
pub struct EpisodeId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct an episode identifier.
pub fn EpisodeId::new(value : String) -> EpisodeId raise MemoryError {
  { value: checked_identifier("EpisodeId", value) }
}

///|
/// Return the immutable textual value.
pub fn EpisodeId::value(self : EpisodeId) -> String {
  self.value
}

///|
/// An opaque caller-supplied entity identifier.
pub struct EntityId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct an entity identifier.
pub fn EntityId::new(value : String) -> EntityId raise MemoryError {
  { value: checked_identifier("EntityId", value) }
}

///|
/// Return the immutable textual value.
pub fn EntityId::value(self : EntityId) -> String {
  self.value
}

///|
/// An opaque caller-supplied fact identifier.
pub struct FactId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct a fact identifier.
pub fn FactId::new(value : String) -> FactId raise MemoryError {
  { value: checked_identifier("FactId", value) }
}

///|
/// Return the immutable textual value.
pub fn FactId::value(self : FactId) -> String {
  self.value
}

///|
/// An opaque caller-supplied isolation-group identifier.
pub struct GroupId {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct a group identifier.
pub fn GroupId::new(value : String) -> GroupId raise MemoryError {
  { value: checked_identifier("GroupId", value) }
}

///|
/// Return the immutable textual value.
pub fn GroupId::value(self : GroupId) -> String {
  self.value
}

///|
/// A lowercase hexadecimal SHA-256 digest.
pub struct Digest256 {
  priv value : String
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Validate and construct a 64-character lowercase hexadecimal digest.
pub fn Digest256::new(value : String) -> Digest256 raise MemoryError {
  if value.length() != 64 {
    raise InvalidDigest("must contain exactly 64 lowercase hexadecimal digits")
  }
  for index in 0..<64 {
    let code = value[index].to_int()
    let decimal = code >= 48 && code <= 57
    let lowercase_hex = code >= 97 && code <= 102
    if !decimal && !lowercase_hex {
      raise InvalidDigest("must contain only lowercase hexadecimal digits")
    }
  }
  { value, }
}

///|
/// Return the immutable lowercase hexadecimal value.
pub fn Digest256::value(self : Digest256) -> String {
  self.value
}
