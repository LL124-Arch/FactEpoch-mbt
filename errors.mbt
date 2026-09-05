// SPDX-License-Identifier: Apache-2.0

///|
/// A typed reference whose target belongs to the wrong isolation group.
pub(all) enum GroupReference {
  SubjectReference(EntityId)
  ObjectReference(EntityId)
  ProvenanceReference(EpisodeId)
} derive(Eq, @debug.Debug)

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
  InvalidLimit(Int)
  InvalidTimeRange(String, Timestamp, Timestamp)
  InvalidSequence(Int64)
  EventIdConflict(EventId)
  StreamMismatch(String, String)
  SequenceNotIncreasing(Int64, Int64)
  RecordedAtRegression(Timestamp, Timestamp)
  EpisodeIdConflict(EpisodeId)
  EntityIdConflict(EntityId)
  FactIdConflict(FactId)
  DuplicateFactReference(FactId)
  MissingFact(FactId)
  FactAlreadyClosed(FactId)
  ConflictDecisionMismatch(String)
  SupersessionGuardFailed(SupersessionGuard)
  MissingEntity(EntityId)
  MissingEpisode(EpisodeId)
  GroupMismatch(GroupReference)
} derive(Eq, @debug.Debug)
