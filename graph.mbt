// SPDX-License-Identifier: Apache-2.0

///|
/// An in-memory graph. Event state is added by the next implementation stage.
pub struct MemoryGraph {
  priv _event_count : Int
}

///|
/// Construct an empty graph without reading a clock, file, or network source.
pub fn MemoryGraph::new() -> MemoryGraph {
  { _event_count: 0 }
}
