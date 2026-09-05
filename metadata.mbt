// SPDX-License-Identifier: Apache-2.0

///|
/// Canonically ordered string metadata with unique, non-empty keys.
pub struct Metadata {
  priv entries : Array[(String, String)]
} derive(Eq)

///|
/// Construct empty metadata.
pub fn Metadata::empty() -> Metadata {
  { entries: [] }
}

///|
/// Copy, validate, and sort metadata by key.
pub fn Metadata::new(
  entries : Array[(String, String)],
) -> Metadata raise MemoryError {
  let sorted = entries.copy()
  sorted.sort_by((left, right) => String::compare(left.0, right.0))
  for index in 0..<sorted.length() {
    let key = sorted[index].0
    if key.is_empty() {
      raise InvalidField("metadata.key", "must not be empty")
    }
    if index > 0 && sorted[index - 1].0 == key {
      raise DuplicateMetadataKey(key)
    }
  }
  { entries: sorted }
}

///|
/// Return a defensive copy in canonical key order.
pub fn Metadata::entries(self : Metadata) -> Array[(String, String)] {
  self.entries.copy()
}

///|
/// Return the number of metadata entries.
pub fn Metadata::length(self : Metadata) -> Int {
  self.entries.length()
}

///|
/// Test whether the metadata set is empty.
pub fn Metadata::is_empty(self : Metadata) -> Bool {
  self.entries.is_empty()
}
