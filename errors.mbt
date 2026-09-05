// SPDX-License-Identifier: Apache-2.0

///|
/// Stable validation categories returned by the portable FactEpoch core.
pub(all) suberror MemoryError {
  InvalidIdentifier(String, String)
  InvalidDigest(String)
  InvalidInterval(Timestamp, Timestamp)
  InvalidField(String, String)
  InvalidEvidence(String)
  DuplicateMetadataKey(String)
  InvalidConfidence(Int)
} derive(Eq, @debug.Debug)
