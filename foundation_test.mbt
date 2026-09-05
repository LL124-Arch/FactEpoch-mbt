///|
fn sample_ids() -> (
  @factepoch.EpisodeId,
  @factepoch.EntityId,
  @factepoch.GroupId,
) raise {
  (
    @factepoch.EpisodeId::new("episode-1"),
    @factepoch.EntityId::new("entity-1"),
    @factepoch.GroupId::new("group-1"),
  )
}

///|
test "opaque identifiers validate and compare by UTF-8 value" {
  let first = @factepoch.EventId::new("event-01")
  let second = @factepoch.EventId::new("event-02")
  inspect(first.value(), content="event-01")
  inspect(first < second, content="true")
  inspect(first == @factepoch.EventId::new("event-01"), content="true")
  let private_use = @factepoch.EventId::new("\u{e000}")
  let supplementary = @factepoch.EventId::new("\u{10000}")
  inspect(private_use < supplementary, content="true")
  inspect(@factepoch.FactId::new("fact-1").value(), content="fact-1")
  inspect(@factepoch.EpisodeId::new("episode-1").value(), content="episode-1")
  inspect(@factepoch.EntityId::new("entity-1").value(), content="entity-1")
  inspect(@factepoch.GroupId::new("group-1").value(), content="group-1")
  inspect(
    @factepoch.EventId::new("中".repeat(85)).value().length(),
    content="85",
  )
  try @factepoch.EventId::new("") catch {
    InvalidIdentifier(kind, _) => inspect(kind, content="EventId")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty identifier must fail")
  }
  try @factepoch.EventId::new("中".repeat(86)) catch {
    InvalidIdentifier(kind, _) => inspect(kind, content="EventId")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("identifier over 255 UTF-8 bytes must fail")
  }
}

///|
test "digest accepts only lowercase SHA-256 text" {
  let digest = @factepoch.Digest256::new(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  inspect(
    digest.value(),
    content="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  try
    @factepoch.Digest256::new(
      "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
    )
  catch {
    InvalidDigest(_) => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("uppercase digest must fail")
  }
}

///|
test "timestamps and half-open intervals preserve millisecond boundaries" {
  let start = @factepoch.Timestamp::from_unix_millis(1_000L)
  let end = @factepoch.Timestamp::from_unix_millis(2_000L)
  let interval = @factepoch.ValidInterval::new(start, Some(end))
  inspect(start.to_unix_millis(), content="1000")
  inspect(interval.contains(start), content="true")
  inspect(interval.start().to_unix_millis(), content="1000")
  inspect(
    interval.end().map(t => t.to_unix_millis()) == Some(2_000L),
    content="true",
  )
  inspect(interval.contains(end), content="false")
  inspect(
    interval.overlaps(
      @factepoch.ValidInterval::new(
        @factepoch.Timestamp::from_unix_millis(1_999L),
        Some(@factepoch.Timestamp::from_unix_millis(2_001L)),
      ),
    ),
    content="true",
  )
  inspect(
    interval.overlaps(
      @factepoch.ValidInterval::new(
        end,
        Some(@factepoch.Timestamp::from_unix_millis(3_000L)),
      ),
    ),
    content="false",
  )
  try @factepoch.ValidInterval::new(start, Some(start)) catch {
    InvalidInterval(_, _) => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty interval must fail")
  }
}

///|
test "metadata is copied, sorted, and rejects duplicate keys" {
  inspect(@factepoch.Metadata::empty().is_empty(), content="true")
  let input = [("z", "last"), ("a", "first")]
  let metadata = @factepoch.Metadata::new(input)
  input[0] = ("changed", "outside")
  let entries = metadata.entries()
  inspect(entries[0].0, content="a")
  inspect(entries[0].1, content="first")
  inspect(entries[1].0, content="z")
  let returned = metadata.entries()
  returned.clear()
  inspect(metadata.length(), content="2")
  try @factepoch.Metadata::new([("same", "one"), ("same", "two")]) catch {
    DuplicateMetadataKey(key) => inspect(key, content="same")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("duplicate metadata key must fail")
  }
}

///|
test "provenance normalizes sources and validates UTF-8 evidence offsets" {
  let (episode_id, _, _) = sample_ids()
  let other = @factepoch.EpisodeId::new("episode-2")
  let digest = @factepoch.Digest256::new(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  let span = @factepoch.EvidenceSpan::new(episode_id, 1, 4, Some(digest))
  inspect(span.episode_id().value(), content="episode-1")
  inspect(span.start_utf8(), content="1")
  inspect(span.end_utf8(), content="4")
  inspect(span.excerpt_digest() == Some(digest), content="true")
  span.validate_for_body("a中b")
  let provenance = @factepoch.Provenance::new(
    [other, episode_id, episode_id],
    [span, span],
    Some("fixture-v1"),
  )
  let source_ids = provenance.episode_ids()
  inspect(source_ids[0].value(), content="episode-1")
  inspect(source_ids[1].value(), content="episode-2")
  let returned_evidence = provenance.evidence()
  returned_evidence.clear()
  inspect(provenance.evidence().length(), content="1")
  match provenance.extractor() {
    Some(value) => inspect(value, content="fixture-v1")
    None => fail("expected extractor label")
  }
  try
    @factepoch.EvidenceSpan::new(episode_id, 2, 4, None).validate_for_body(
      "a中b",
    )
  catch {
    InvalidEvidence(_) => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("offset inside a UTF-8 code point must fail")
  }
  try
    @factepoch.EvidenceSpan::new(episode_id, 1, 6, None).validate_for_body(
      "a中b",
    )
  catch {
    InvalidEvidence(_) => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("evidence ending beyond the UTF-8 body must fail")
  }
  let foreign_span = @factepoch.EvidenceSpan::new(other, 0, 1, None)
  try @factepoch.Provenance::new([episode_id], [foreign_span], None) catch {
    InvalidEvidence(_) => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("evidence episode absent from provenance must fail")
  }
  try @factepoch.Provenance::new([], [], None) catch {
    InvalidField(field, _) => inspect(field, content="episode_ids")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("provenance without an episode must fail")
  }
}

///|
test "domain constructors retain validated data without exposing mutable metadata" {
  let (episode_id, entity_id, group_id) = sample_ids()
  let second_entity = @factepoch.EntityId::new("entity-2")
  let metadata = @factepoch.Metadata::new([("origin", "fixture")])
  let occurred_from = @factepoch.Timestamp::from_unix_millis(900L)
  let episode = @factepoch.Episode::new(
    episode_id,
    group_id,
    "Alice chose MoonBit.",
    Some("fixture://episode-1"),
    Some(occurred_from),
    None,
    metadata,
  )
  inspect(episode.id().value(), content="episode-1")
  inspect(episode.group_id().value(), content="group-1")
  inspect(episode.body(), content="Alice chose MoonBit.")
  match episode.source_uri() {
    Some(value) => inspect(value, content="fixture://episode-1")
    None => fail("expected source URI")
  }
  match episode.occurred_from() {
    Some(value) => inspect(value.to_unix_millis(), content="900")
    None => fail("expected occurrence start")
  }
  inspect(episode.occurred_to() == None, content="true")
  inspect(episode.metadata().length(), content="1")
  let entity = @factepoch.Entity::new(
    entity_id,
    group_id,
    "Alice",
    "person",
    Some("repository owner"),
    metadata,
  )
  inspect(entity.id().value(), content="entity-1")
  inspect(entity.group_id().value(), content="group-1")
  inspect(entity.name(), content="Alice")
  inspect(entity.kind(), content="person")
  match entity.summary() {
    Some(value) => inspect(value, content="repository owner")
    None => fail("expected entity summary")
  }
  inspect(entity.metadata().length(), content="1")
  let provenance = @factepoch.Provenance::new([episode_id], [], None)
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-1"),
    group_id,
    entity_id,
    "prefers_language",
    EntityRef(second_entity),
    "Alice prefers MoonBit",
    @factepoch.Timestamp::from_unix_millis(1_000L),
    None,
    9_500,
    provenance,
  )
  inspect(fact.id().value(), content="fact-1")
  inspect(fact.group_id().value(), content="group-1")
  inspect(fact.subject().value(), content="entity-1")
  inspect(fact.predicate(), content="prefers_language")
  match fact.object() {
    EntityRef(id) => inspect(id.value(), content="entity-2")
    _ => fail("expected entity reference")
  }
  inspect(fact.statement(), content="Alice prefers MoonBit")
  inspect(fact.valid_interval().contains(fact.valid_from()), content="true")
  inspect(fact.valid_to() == None, content="true")
  inspect(fact.confidence_basis_points(), content="9500")
  inspect(fact.provenance().episode_ids().length(), content="1")
  let _empty = @factepoch.MemoryGraph::new()
}

///|
test "domain constructors reject malformed fields and confidence" {
  let (episode_id, entity_id, group_id) = sample_ids()
  let metadata = @factepoch.Metadata::empty()
  try
    @factepoch.Entity::new(entity_id, group_id, "", "person", None, metadata)
  catch {
    InvalidField(field, _) => inspect(field, content="name")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty entity name must fail")
  }
  let provenance = @factepoch.Provenance::new([episode_id], [], None)
  try
    @factepoch.FactAssertion::new(
      @factepoch.FactId::new("fact-1"),
      group_id,
      entity_id,
      "predicate",
      Literal("value"),
      "statement",
      @factepoch.Timestamp::from_unix_millis(1_000L),
      None,
      10_001,
      provenance,
    )
  catch {
    InvalidConfidence(value) => inspect(value, content="10001")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("out-of-range confidence must fail")
  }
}

///|
test "fact predicates reject normalized emptiness but retain source spelling" {
  let (episode_id, entity_id, group_id) = sample_ids()
  let provenance = @factepoch.Provenance::new([episode_id], [], None)
  try
    @factepoch.FactAssertion::new(
      @factepoch.FactId::new("fact-whitespace-predicate"),
      group_id,
      entity_id,
      " \t\r\n ",
      Literal("value"),
      "statement",
      @factepoch.Timestamp::from_unix_millis(1_000L),
      None,
      9_000,
      provenance,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="predicate")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("ASCII-whitespace-only predicate must fail")
  }
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-spelled-predicate"),
    group_id,
    entity_id,
    "  Prefers\tLANGUAGE  ",
    Literal("MoonBit"),
    "Alice prefers MoonBit",
    @factepoch.Timestamp::from_unix_millis(1_000L),
    None,
    9_000,
    provenance,
  )
  inspect(fact.predicate(), content="  Prefers\tLANGUAGE  ")
}

///|
test "domain text fields are non-empty and occurrence bounds are coherent" {
  let (episode_id, entity_id, group_id) = sample_ids()
  let metadata = @factepoch.Metadata::empty()
  try @factepoch.GroupId::new("") catch {
    InvalidIdentifier(kind, _) => inspect(kind, content="GroupId")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty group ID must fail")
  }
  try
    @factepoch.Episode::new(
      episode_id,
      group_id,
      "",
      None,
      None,
      None,
      metadata,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="body")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty episode body must fail")
  }
  try
    @factepoch.Episode::new(
      episode_id,
      group_id,
      "body",
      None,
      None,
      Some(@factepoch.Timestamp::from_unix_millis(2_000L)),
      metadata,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="occurred_to")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("occurrence end without a start must fail")
  }
  try
    @factepoch.Entity::new(entity_id, group_id, "entity", "", None, metadata)
  catch {
    InvalidField(field, _) => inspect(field, content="kind")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty entity kind must fail")
  }
  let provenance = @factepoch.Provenance::new([episode_id], [], None)
  try
    @factepoch.FactAssertion::new(
      @factepoch.FactId::new("fact-empty-literal"),
      group_id,
      entity_id,
      "predicate",
      Literal(""),
      "statement",
      @factepoch.Timestamp::from_unix_millis(1_000L),
      None,
      10_000,
      provenance,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="object.literal")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty literal must fail")
  }
}
