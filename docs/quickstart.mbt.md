# Quickstart

The foundation API is available. This example constructs validated source material, an entity, and a fact without reading a clock or touching external state. This Markdown file is the test source: the `docs` package compiles and executes its `mbt check` block on every supported core target.

```mbt check
///|
test "foundation quickstart constructs a source-backed fact" {
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
  let _graph = @factepoch.MemoryGraph::new()
}
```

Run it with:

```text
moon test docs --target all
```

The graph is intentionally still empty: event application and bitemporal queries are the next capability, not a hidden part of this foundation example.
