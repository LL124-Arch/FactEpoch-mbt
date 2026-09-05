///|
fn stored_fact_fixture() -> (Episode, Entity, FactAssertion) raise MemoryError {
  let group = GroupId::new("stored-fact")
  let episode = Episode::new(
    EpisodeId::new("episode"),
    group,
    "Mira selected MoonBit.",
    None,
    None,
    None,
    Metadata::empty(),
  )
  let entity = Entity::new(
    EntityId::new("mira"),
    group,
    "Mira",
    "person",
    None,
    Metadata::empty(),
  )
  let fact = FactAssertion::new(
    FactId::new("selection"),
    group,
    entity.id(),
    "selected",
    Literal("MoonBit"),
    "Mira selected MoonBit",
    Timestamp::from_unix_millis(500L),
    None,
    10_000,
    Provenance::new([episode.id()], [], None),
  )
  (episode, entity, fact)
}

///|
test "equal fact replay preserves the first activation envelope" {
  let (episode, entity, fact) = stored_fact_fixture()
  let graph = MemoryGraph::new()
  let at = Timestamp::from_unix_millis(1_000L)
  let later = Timestamp::from_unix_millis(2_000L)
  let batch = [
    RecordedEvent::new(
      "stored-fact",
      1L,
      EventId::new("episode"),
      at,
      RecordEpisode(episode),
    ),
    RecordedEvent::new(
      "stored-fact",
      2L,
      EventId::new("entity"),
      at,
      PutEntity(entity),
    ),
    RecordedEvent::new(
      "stored-fact",
      3L,
      EventId::new("first-activation"),
      at,
      AssertFact(fact),
    ),
    RecordedEvent::new(
      "stored-fact",
      4L,
      EventId::new("semantic-replay"),
      later,
      AssertFact(fact),
    ),
  ]
  match graph.apply(batch) {
    Err(_) => fail("fixture must apply")
    Ok(_) => ()
  }
  inspect(graph.facts.length(), content="1")
  inspect(graph.facts[0].assertion == fact, content="true")
  inspect(
    graph.facts[0].activation_event_id.value(),
    content="first-activation",
  )
  inspect(
    graph.facts[0].activation_recorded_at.to_unix_millis(),
    content="1000",
  )
  inspect(graph.facts[0].closure_event_id == None, content="true")
  inspect(graph.facts[0].closure_recorded_at == None, content="true")
}
