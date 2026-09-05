///|
fn event_fixture() -> (
  @factepoch.GroupId,
  @factepoch.Episode,
  @factepoch.Entity,
  @factepoch.Entity,
  @factepoch.FactAssertion,
) raise {
  let group = @factepoch.GroupId::new("team-a")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-1"),
    group,
    "Rin chose MoonBit.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("entity-rin"),
    group,
    "Rin",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let object = @factepoch.Entity::new(
    @factepoch.EntityId::new("entity-moonbit"),
    group,
    "MoonBit",
    "language",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new(
    [episode.id()],
    [@factepoch.EvidenceSpan::new(episode.id(), 0, 3, None)],
    Some("fixture"),
  )
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-1"),
    group,
    subject.id(),
    "uses",
    EntityRef(object.id()),
    "Rin uses MoonBit",
    @factepoch.Timestamp::from_unix_millis(900L),
    None,
    9_000,
    provenance,
  )
  (group, episode, subject, object, fact)
}

///|
fn recorded(
  seq : Int64,
  id : String,
  at : Int64,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "memory-a",
    seq,
    @factepoch.EventId::new(id),
    @factepoch.Timestamp::from_unix_millis(at),
    event,
  )
}

///|
fn require_apply(
  result : Result[@factepoch.ApplyReport, @factepoch.MemoryError],
) -> @factepoch.ApplyReport {
  match result {
    Ok(report) => report
    Err(_) => abort("expected event batch to apply")
  }
}

///|
test "apply accepts same-batch references and publishes one ordered snapshot" {
  let (_, episode, subject, object, fact) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let report = require_apply(
    graph.apply([
      recorded(1L, "event-episode", 1_000L, RecordEpisode(episode)),
      recorded(2L, "event-subject", 1_000L, PutEntity(subject)),
      recorded(3L, "event-object", 1_001L, PutEntity(object)),
      recorded(4L, "event-fact", 1_002L, AssertFact(fact)),
    ]),
  )
  inspect(report.accepted_event_ids().length(), content="4")
  inspect(report.idempotent_event_ids().length(), content="0")
  inspect(report.created_episode_count(), content="1")
  inspect(report.created_entity_count(), content="2")
  inspect(report.created_fact_count(), content="1")
  inspect(report.event_count(), content="4")
  let events = graph.snapshot_events()
  inspect(events.length(), content="4")
  inspect(events[0].seq(), content="1")
  inspect(events[3].event_id().value(), content="event-fact")
}

///|
test "a final-event failure rolls back the whole batch" {
  let (group, episode, subject, _, _) = event_fixture()
  let missing_object_fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-missing-object"),
    group,
    subject.id(),
    "uses",
    EntityRef(@factepoch.EntityId::new("missing-object")),
    "Rin uses an unavailable tool",
    @factepoch.Timestamp::from_unix_millis(900L),
    None,
    8_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let graph = @factepoch.MemoryGraph::new()
  match
    graph.apply([
      recorded(1L, "event-episode", 1_000L, RecordEpisode(episode)),
      recorded(2L, "event-subject", 1_001L, PutEntity(subject)),
      recorded(3L, "event-bad-fact", 1_002L, AssertFact(missing_object_fact)),
    ]) {
    Err(MissingEntity(id)) => inspect(id.value(), content="missing-object")
    _ => fail("expected missing object entity")
  }
  inspect(graph.snapshot_events().length(), content="0")
  let retry_event = recorded(
    1L,
    "event-episode",
    1_000L,
    RecordEpisode(episode),
  )
  let retry = require_apply(graph.apply([retry_event]))
  inspect(retry.event_count(), content="1")
  let duplicate = require_apply(graph.apply([retry_event]))
  inspect(duplicate.accepted_event_ids().length(), content="0")
  inspect(duplicate.idempotent_event_ids().length(), content="1")
}

///|
test "event identity is checked before ordering and protects payload identity" {
  let (_, episode, subject, _, _) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let first = recorded(1L, "event-stable", 1_000L, RecordEpisode(episode))
  ignore(require_apply(graph.apply([first])))
  ignore(
    require_apply(
      graph.apply([recorded(2L, "event-next", 1_001L, PutEntity(subject))]),
    ),
  )
  let repeated = require_apply(graph.apply([first]))
  inspect(repeated.accepted_event_ids().length(), content="0")
  inspect(repeated.idempotent_event_ids()[0].value(), content="event-stable")
  let duplicate_ids = repeated.idempotent_event_ids()
  duplicate_ids.clear()
  inspect(repeated.idempotent_event_ids().length(), content="1")
  inspect(repeated.event_count(), content="2")
  let changed = recorded(3L, "event-stable", 1_002L, PutEntity(subject))
  match graph.apply([changed]) {
    Err(EventIdConflict(id)) => inspect(id.value(), content="event-stable")
    _ => fail("expected conflicting event payload")
  }
  inspect(graph.snapshot_events().length(), content="2")
}

///|
test "an exact duplicate inside one batch is reported once without being stored twice" {
  let (_, episode, _, _, _) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let event = recorded(1L, "event-once", 1_000L, RecordEpisode(episode))
  let report = require_apply(graph.apply([event, event]))
  let accepted = report.accepted_event_ids()
  let idempotent = report.idempotent_event_ids()
  inspect(accepted.length(), content="1")
  inspect(accepted[0].value(), content="event-once")
  inspect(idempotent.length(), content="1")
  inspect(idempotent[0].value(), content="event-once")
  inspect(report.event_count(), content="1")
  inspect(graph.snapshot_events().length(), content="1")
}

///|
test "event ID conflict wins over stream and order checks and rolls cursors back" {
  let (_, episode, subject, _, _) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let first = recorded(1L, "event-collision", 2_000L, RecordEpisode(episode))
  let changed = @factepoch.RecordedEvent::new(
    "memory-b",
    1L,
    @factepoch.EventId::new("event-collision"),
    @factepoch.Timestamp::from_unix_millis(1_500L),
    PutEntity(subject),
  )
  match graph.apply([first, changed]) {
    Err(EventIdConflict(id)) => inspect(id.value(), content="event-collision")
    _ => fail("event identity must be checked before stream and order")
  }
  inspect(graph.snapshot_events().length(), content="0")
  let retry = require_apply(
    graph.apply([
      recorded(1L, "event-after-rollback", 1_000L, RecordEpisode(episode)),
    ]),
  )
  inspect(retry.accepted_event_ids().length(), content="1")
  inspect(retry.event_count(), content="1")
}

///|
test "stream sequence and recorded-time invariants reject new events" {
  let (_, episode, subject, object, _) = event_fixture()
  try
    @factepoch.RecordedEvent::new(
      "",
      1L,
      @factepoch.EventId::new("bad-stream"),
      @factepoch.Timestamp::from_unix_millis(1_000L),
      RecordEpisode(episode),
    )
  catch {
    InvalidField(field, _) => inspect(field, content="stream_id")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty stream must fail")
  }
  try recorded(0L, "bad-seq", 1_000L, RecordEpisode(episode)) catch {
    InvalidSequence(value) => inspect(value, content="0")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("non-positive sequence must fail")
  }
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    require_apply(
      graph.apply([recorded(2L, "event-first", 2_000L, RecordEpisode(episode))]),
    ),
  )
  match
    graph.apply([
      @factepoch.RecordedEvent::new(
        "memory-b",
        3L,
        @factepoch.EventId::new("wrong-stream"),
        @factepoch.Timestamp::from_unix_millis(2_001L),
        PutEntity(subject),
      ),
    ]) {
    Err(StreamMismatch(_, actual)) => inspect(actual, content="memory-b")
    _ => fail("expected stream mismatch")
  }
  match graph.apply([recorded(2L, "bad-order", 2_001L, PutEntity(subject))]) {
    Err(SequenceNotIncreasing(previous, next)) => {
      inspect(previous, content="2")
      inspect(next, content="2")
    }
    _ => fail("expected sequence order failure")
  }
  match graph.apply([recorded(3L, "bad-time", 1_999L, PutEntity(object))]) {
    Err(RecordedAtRegression(_, next)) =>
      inspect(next.to_unix_millis(), content="1999")
    _ => fail("expected recorded-time regression")
  }
  inspect(graph.snapshot_events().length(), content="1")
}

///|
test "domain IDs make equal writes no-ops and reject changed objects" {
  let (_, episode, subject, _, _) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let first = require_apply(
    graph.apply([
      recorded(1L, "episode-a", 1_000L, RecordEpisode(episode)),
      recorded(2L, "entity-a", 1_001L, PutEntity(subject)),
    ]),
  )
  inspect(first.created_episode_count(), content="1")
  inspect(first.created_entity_count(), content="1")
  let duplicate = require_apply(
    graph.apply([
      recorded(3L, "episode-b", 1_002L, RecordEpisode(episode)),
      recorded(4L, "entity-b", 1_003L, PutEntity(subject)),
    ]),
  )
  inspect(duplicate.accepted_event_ids().length(), content="2")
  inspect(duplicate.created_episode_count(), content="0")
  inspect(duplicate.created_entity_count(), content="0")
  let changed_episode = @factepoch.Episode::new(
    episode.id(),
    episode.group_id(),
    "Changed private body",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  match
    graph.apply([
      recorded(5L, "episode-conflict", 1_004L, RecordEpisode(changed_episode)),
    ]) {
    Err(EpisodeIdConflict(id)) => inspect(id.value(), content="episode-1")
    _ => fail("expected episode identity conflict")
  }
  let changed_entity = @factepoch.Entity::new(
    subject.id(),
    subject.group_id(),
    "Different name",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  match
    graph.apply([
      recorded(5L, "entity-conflict", 1_004L, PutEntity(changed_entity)),
    ]) {
    Err(EntityIdConflict(id)) => inspect(id.value(), content="entity-rin")
    _ => fail("expected entity identity conflict")
  }
  inspect(graph.snapshot_events().length(), content="4")
}

///|
test "fact identity accepts an equal semantic replay and rejects changed text" {
  let (_, episode, subject, object, fact) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let initial = require_apply(
    graph.apply([
      recorded(1L, "episode", 1_000L, RecordEpisode(episode)),
      recorded(2L, "subject", 1_001L, PutEntity(subject)),
      recorded(3L, "object", 1_002L, PutEntity(object)),
      recorded(4L, "fact-a", 1_003L, AssertFact(fact)),
      recorded(5L, "fact-b", 1_004L, AssertFact(fact)),
    ]),
  )
  inspect(initial.accepted_event_ids().length(), content="5")
  inspect(initial.created_fact_count(), content="1")
  let changed = @factepoch.FactAssertion::new(
    fact.id(),
    fact.group_id(),
    fact.subject(),
    fact.predicate(),
    fact.object(),
    "Changed assertion text",
    fact.valid_from(),
    fact.valid_to(),
    fact.confidence_basis_points(),
    fact.provenance(),
  )
  match
    graph.apply([recorded(6L, "fact-conflict", 1_005L, AssertFact(changed))]) {
    Err(FactIdConflict(id)) => inspect(id.value(), content="fact-1")
    _ => fail("expected fact identity conflict")
  }
  inspect(graph.snapshot_events().length(), content="5")
}

///|
test "fact references must exist inside the same isolation group" {
  let (group, episode, subject, object, fact) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    require_apply(
      graph.apply([recorded(1L, "episode", 1_000L, RecordEpisode(episode))]),
    ),
  )
  match
    graph.apply([recorded(2L, "fact-missing-subject", 1_001L, AssertFact(fact))]) {
    Err(MissingEntity(id)) => inspect(id.value(), content="entity-rin")
    _ => fail("expected missing subject")
  }
  let other_group = @factepoch.GroupId::new("team-b")
  let foreign_subject = @factepoch.Entity::new(
    subject.id(),
    other_group,
    "Rin",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let foreign_object = @factepoch.Entity::new(
    object.id(),
    other_group,
    "MoonBit",
    "language",
    None,
    @factepoch.Metadata::empty(),
  )
  ignore(
    require_apply(
      graph.apply([
        recorded(2L, "foreign-subject", 1_001L, PutEntity(foreign_subject)),
        recorded(3L, "foreign-object", 1_002L, PutEntity(foreign_object)),
      ]),
    ),
  )
  match
    graph.apply([recorded(4L, "fact-wrong-group", 1_003L, AssertFact(fact))]) {
    Err(GroupMismatch(SubjectReference(id))) =>
      inspect(id.value(), content="entity-rin")
    _ => fail("expected subject group mismatch")
  }
  let local_subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("entity-local"),
    group,
    "Local",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  ignore(
    require_apply(
      graph.apply([
        recorded(4L, "local-subject", 1_003L, PutEntity(local_subject)),
      ]),
    ),
  )
  let wrong_object_group = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-wrong-object-group"),
    group,
    local_subject.id(),
    "uses",
    EntityRef(foreign_object.id()),
    "Local uses MoonBit",
    @factepoch.Timestamp::from_unix_millis(900L),
    None,
    8_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  match
    graph.apply([
      recorded(5L, "wrong-object-group", 1_004L, AssertFact(wrong_object_group)),
    ]) {
    Err(GroupMismatch(ObjectReference(id))) =>
      inspect(id.value(), content="entity-moonbit")
    _ => fail("expected object group mismatch")
  }
  let missing_episode_fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-missing-episode"),
    group,
    local_subject.id(),
    "uses",
    Literal("MoonBit"),
    "Local uses MoonBit",
    @factepoch.Timestamp::from_unix_millis(900L),
    None,
    8_000,
    @factepoch.Provenance::new(
      [@factepoch.EpisodeId::new("missing-episode")],
      [],
      None,
    ),
  )
  match
    graph.apply([
      recorded(
        5L,
        "fact-missing-episode",
        1_004L,
        AssertFact(missing_episode_fact),
      ),
    ]) {
    Err(MissingEpisode(id)) => inspect(id.value(), content="missing-episode")
    _ => fail("expected missing provenance episode")
  }
  let foreign_episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("foreign-episode"),
    other_group,
    "Foreign source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  ignore(
    require_apply(
      graph.apply([
        recorded(5L, "foreign-episode", 1_004L, RecordEpisode(foreign_episode)),
      ]),
    ),
  )
  let wrong_provenance_group = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-wrong-provenance-group"),
    group,
    local_subject.id(),
    "uses",
    Literal("MoonBit"),
    "Local uses MoonBit",
    @factepoch.Timestamp::from_unix_millis(900L),
    None,
    8_000,
    @factepoch.Provenance::new([foreign_episode.id()], [], None),
  )
  match
    graph.apply([
      recorded(
        6L,
        "wrong-provenance-group",
        1_005L,
        AssertFact(wrong_provenance_group),
      ),
    ]) {
    Err(GroupMismatch(ProvenanceReference(id))) =>
      inspect(id.value(), content="foreign-episode")
    _ => fail("expected provenance group mismatch")
  }
}

///|
test "evidence is validated against the stored episode body" {
  let (group, episode, subject, _, _) = event_fixture()
  let invalid = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-invalid-evidence"),
    group,
    subject.id(),
    "uses",
    Literal("MoonBit"),
    "Rin uses MoonBit",
    @factepoch.Timestamp::from_unix_millis(900L),
    None,
    8_000,
    @factepoch.Provenance::new(
      [episode.id()],
      [@factepoch.EvidenceSpan::new(episode.id(), 0, 99, None)],
      None,
    ),
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    require_apply(
      graph.apply([
        recorded(1L, "episode", 1_000L, RecordEpisode(episode)),
        recorded(2L, "subject", 1_001L, PutEntity(subject)),
      ]),
    ),
  )
  match
    graph.apply([recorded(3L, "invalid-evidence", 1_002L, AssertFact(invalid))]) {
    Err(InvalidEvidence(_)) => ()
    _ => fail("expected evidence bounds failure")
  }
  inspect(graph.snapshot_events().length(), content="2")
}

///|
test "reports and snapshots return defensive arrays" {
  let (_, episode, subject, _, _) = event_fixture()
  let graph = @factepoch.MemoryGraph::new()
  let report = require_apply(
    graph.apply([
      recorded(1L, "episode", 1_000L, RecordEpisode(episode)),
      recorded(2L, "subject", 1_001L, PutEntity(subject)),
    ]),
  )
  let accepted = report.accepted_event_ids()
  accepted.clear()
  inspect(report.accepted_event_ids().length(), content="2")
  let snapshot = graph.snapshot_events()
  snapshot.clear()
  inspect(graph.snapshot_events().length(), content="2")
}

///|
test "replay is equivalent and failed replay returns no graph" {
  let (_, episode, subject, object, fact) = event_fixture()
  let source = @factepoch.MemoryGraph::new()
  ignore(
    require_apply(
      source.apply([
        recorded(1L, "episode", 1_000L, RecordEpisode(episode)),
        recorded(2L, "subject", 1_001L, PutEntity(subject)),
        recorded(3L, "object", 1_002L, PutEntity(object)),
        recorded(4L, "fact", 1_003L, AssertFact(fact)),
      ]),
    ),
  )
  match @factepoch.MemoryGraph::replay(source.snapshot_events()) {
    Ok(replayed) =>
      inspect(
        replayed.snapshot_events() == source.snapshot_events(),
        content="true",
      )
    Err(_) => fail("valid snapshot must replay")
  }
  match
    @factepoch.MemoryGraph::replay([
      recorded(1L, "fact-first", 1_000L, AssertFact(fact)),
    ]) {
    Err(MissingEntity(id)) => inspect(id.value(), content="entity-rin")
    _ => fail("invalid replay must return a typed error")
  }
}

///|
test "indexed replay preserves a moderately sized ordered stream" {
  let events : Array[@factepoch.RecordedEvent] = []
  let group = @factepoch.GroupId::new("index-regression")
  for number in 1..<=256 {
    let suffix = number.to_string()
    let episode = @factepoch.Episode::new(
      @factepoch.EpisodeId::new("episode-" + suffix),
      group,
      "body-" + suffix,
      None,
      None,
      None,
      @factepoch.Metadata::empty(),
    )
    events.push(
      @factepoch.RecordedEvent::new(
        "index-regression",
        number.to_int64(),
        @factepoch.EventId::new("event-" + suffix),
        @factepoch.Timestamp::from_unix_millis(10_000L + number.to_int64()),
        RecordEpisode(episode),
      ),
    )
  }
  let graph = @factepoch.MemoryGraph::new()
  let report = require_apply(graph.apply(events))
  inspect(report.created_episode_count(), content="256")
  inspect(report.event_count(), content="256")
  let snapshot = graph.snapshot_events()
  match @factepoch.MemoryGraph::replay(snapshot) {
    Err(_) => fail("indexed stream must replay")
    Ok(replayed) => {
      inspect(replayed.snapshot_events() == snapshot, content="true")
      let duplicate = require_apply(replayed.apply([snapshot[0]]))
      inspect(duplicate.idempotent_event_ids().length(), content="1")
      inspect(replayed.snapshot_events().length(), content="256")
    }
  }
}
