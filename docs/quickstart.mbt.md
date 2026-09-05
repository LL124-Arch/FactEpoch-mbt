# Quickstart

This example constructs source material, an entity, and a fact, commits all three as one atomic batch, then asks the same valid-time question immediately before and at the fact's known-time activation. It does not read a clock or touch external state. This Markdown file is the test source: the `docs` package compiles and executes its `mbt check` block on every supported core target.

```mbt check
///|
test "quickstart atomically records a source-backed fact" {
  let group = @factepoch.GroupId::new("personal")
  let episode_id = @factepoch.EpisodeId::new("episode-2026-09-05")
  let episode = @factepoch.Episode::new(
    episode_id,
    group,
    "Lin prefers MoonBit for portable tools.",
    Some("journal://2026-09-05"),
    Some(@factepoch.Timestamp::from_unix_millis(1_787_472_000_000L)),
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("person-lin"),
    group,
    "Lin",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new(
    [episode.id()],
    [],
    Some("manual"),
  )
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("fact-language-1"),
    group,
    subject.id(),
    "prefers_language",
    Literal("MoonBit"),
    "Lin prefers MoonBit",
    @factepoch.Timestamp::from_unix_millis(1_787_472_000_000L),
    None,
    10_000,
    provenance,
  )
  inspect(fact.statement(), content="Lin prefers MoonBit")
  inspect(
    fact
    .valid_interval()
    .contains(@factepoch.Timestamp::from_unix_millis(1_787_472_000_000L)),
    content="true",
  )
  let graph = @factepoch.MemoryGraph::new()
  let recorded_at = @factepoch.Timestamp::from_unix_millis(1_788_249_600_000L)
  let batch = [
    @factepoch.RecordedEvent::new(
      "quickstart",
      1L,
      @factepoch.EventId::new("event-episode-1"),
      recorded_at,
      RecordEpisode(episode),
    ),
    @factepoch.RecordedEvent::new(
      "quickstart",
      2L,
      @factepoch.EventId::new("event-entity-1"),
      recorded_at,
      PutEntity(subject),
    ),
    @factepoch.RecordedEvent::new(
      "quickstart",
      3L,
      @factepoch.EventId::new("event-fact-1"),
      recorded_at,
      AssertFact(fact),
    ),
  ]
  match graph.apply(batch) {
    Ok(report) => {
      inspect(report.accepted_event_ids().length(), content="3")
      inspect(report.created_fact_count(), content="1")
      inspect(report.event_count(), content="3")
    }
    Err(_) => fail("valid quickstart batch must apply")
  }
  inspect(graph.snapshot_events().length(), content="3")
  let valid_at = @factepoch.Timestamp::from_unix_millis(1_787_472_000_000L)
  let filter = @factepoch.FactFilter::new(predicate=" PREFERS_LANGUAGE ")
  let before_activation = @factepoch.FactQuery::new(
    valid_at,
    @factepoch.Timestamp::from_unix_millis(1_788_249_599_999L),
    filter,
  )
  match graph.query(before_activation) {
    Ok(facts) => inspect(facts.length(), content="0")
    Err(_) => fail("valid query must succeed")
  }
  let at_activation = @factepoch.FactQuery::new(valid_at, recorded_at, filter)
  match graph.query(at_activation) {
    Ok(facts) => {
      inspect(facts.length(), content="1")
      inspect(facts[0].fact().statement(), content="Lin prefers MoonBit")
      inspect(facts[0].predicate_key(), content="prefers_language")
      inspect(facts[0].activation_event_id().value(), content="event-fact-1")
    }
    Err(_) => fail("valid query must succeed")
  }
}
```

Run it with:

```text
moon test docs --target all
```

The portable in-memory graph supports deterministic ingestion/replay and activation-only `valid_at × known_at` query, history, and diff. Supersession, retraction, forget-aware projection, and ranked search remain later capabilities.
