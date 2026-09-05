// SPDX-License-Identifier: Apache-2.0

///|
/// A typed reference whose target belongs to the wrong isolation group.
pub(all) enum GroupReference {
  SubjectReference(EntityId)
  ObjectReference(EntityId)
  ProvenanceReference(EpisodeId)
} derive(Eq, @debug.Debug)

///|
/// Identifies an input vector without carrying any vector content.
pub(all) enum VectorSide {
  LeftVector
  RightVector
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
  DuplicateCandidateId(CandidateId)
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
  InvalidVectorDimensions(Int, Int)
  NonFiniteVectorValue(VectorSide, Int)
  NonFiniteVectorComputation
  NonFiniteRankedScore(FactId)
  InvalidRankConstant(Int)
  InvalidMinimumScore
  InvalidCandidateRank(FactId, Int)
  DuplicateRankedCandidate(FactId)
  DuplicateCandidateRank(Int)
  InvalidRankSource
  DuplicateRankSource
  DuplicateFusedCandidate(FactId)
  InvalidNeighborDepth(Int)
} derive(Eq, @debug.Debug)
