// SPDX-License-Identifier: Apache-2.0

///|
/// A UTC Unix timestamp represented as signed milliseconds since the epoch.
pub struct Timestamp {
  priv unix_millis : Int64
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// Construct a timestamp without consulting a system clock.
pub fn Timestamp::from_unix_millis(unix_millis : Int64) -> Timestamp {
  { unix_millis, }
}

///|
/// Return signed UTC Unix milliseconds.
pub fn Timestamp::to_unix_millis(self : Timestamp) -> Int64 {
  self.unix_millis
}

///|
/// A validated half-open interval `[start, end)`; `None` is unbounded above.
pub struct ValidInterval {
  priv start : Timestamp
  priv end : Timestamp?
} derive(Eq, Compare, @debug.Debug)

///|
/// Construct an interval, rejecting an end at or before its start.
pub fn ValidInterval::new(
  start : Timestamp,
  end : Timestamp?,
) -> ValidInterval raise MemoryError {
  match end {
    Some(bound) if bound <= start => raise InvalidInterval(start, bound)
    _ => { start, end }
  }
}

///|
/// Return the inclusive lower bound.
pub fn ValidInterval::start(self : ValidInterval) -> Timestamp {
  self.start
}

///|
/// Return the exclusive upper bound, or `None` for an open interval.
pub fn ValidInterval::end(self : ValidInterval) -> Timestamp? {
  self.end
}

///|
/// Test whether a timestamp is inside this half-open interval.
pub fn ValidInterval::contains(self : ValidInterval, at : Timestamp) -> Bool {
  at >= self.start &&
  (match self.end {
    Some(bound) => at < bound
    None => true
  })
}

///|
/// Test whether two half-open intervals share at least one timestamp.
pub fn ValidInterval::overlaps(
  self : ValidInterval,
  other : ValidInterval,
) -> Bool {
  let self_before_other = match self.end {
    Some(bound) => bound <= other.start
    None => false
  }
  let other_before_self = match other.end {
    Some(bound) => bound <= self.start
    None => false
  }
  !self_before_other && !other_before_self
}
