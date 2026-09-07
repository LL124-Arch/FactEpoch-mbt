// SPDX-License-Identifier: Apache-2.0

///|
fn query_value(
  graph : @factepoch.MemoryGraph,
  group : @factepoch.GroupId,
  user : @factepoch.EntityId,
  valid_at : Int64,
  known_at : Int64,
) -> String raise @factepoch.MemoryError {
  let views = match
    graph.query(
      @factepoch.FactQuery::new(
        @factepoch.Timestamp::from_unix_millis(valid_at),
        @factepoch.Timestamp::from_unix_millis(known_at),
        group,
        user,
        "prefers_drink",
      ),
    ) {
    Ok(v) => v
    Err(e) => raise e
  }
  if views.length() != 1 {
    abort("expected one visible fact")
  }
  match views[0].fact().object() {
    Literal(value) => value
    EntityRef(_) => abort("expected literal")
  }
}

///|
test "late correction changes known time without rewriting the past" {
  let group = @factepoch.GroupId::new("profile")
  let user_id = @factepoch.EntityId::new("mira")
  let old_ep = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("chat-12"),
    group,
    "Mira likes tea",
  )
  let new_ep = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("chat-18"),
    group,
    "Mira switched to coffee",
  )
  let user = @factepoch.Entity::new(user_id, group, "Mira")
  let tea = @factepoch.Fact::new(
    @factepoch.FactId::new("tea"),
    group,
    user_id,
    "prefers_drink",
    Literal("tea"),
    "Mira prefers tea",
    @factepoch.Timestamp::from_unix_millis(100L),
    old_ep.id(),
    confidence=80,
  )
  let coffee = @factepoch.Fact::new(
    @factepoch.FactId::new("coffee"),
    group,
    user_id,
    "prefers_drink",
    Literal("coffee"),
    "Mira prefers coffee",
    @factepoch.Timestamp::from_unix_millis(150L),
    new_ep.id(),
    confidence=95,
  )
  let graph = @factepoch.MemoryGraph::new()
  let result = graph.apply([
    envelope(1L, "episode-old", 110L, RecordEpisode(old_ep)),
    envelope(2L, "user", 111L, PutEntity(user)),
    envelope(3L, "fact-tea", 120L, AssertFact(tea)),
    envelope(4L, "episode-new", 180L, RecordEpisode(new_ep)),
    envelope(5L, "fact-coffee", 181L, SupersedeFact(coffee, [tea.id()])),
  ])
  inspect(result is Ok(_), content="true")
  inspect(query_value(graph, group, user_id, 160L, 140L), content="tea")
  inspect(query_value(graph, group, user_id, 160L, 200L), content="coffee")
  inspect(query_value(graph, group, user_id, 120L, 200L), content="tea")
  let versions = graph.history(
    group,
    user_id,
    "  PREFERS_DRINK  ",
    @factepoch.Timestamp::from_unix_millis(200L),
  )
  match versions {
    Ok(items) => inspect(items.length(), content="2")
    Err(_) => fail("history should succeed")
  }
  let explanation = graph.explain(
    coffee.id(),
    @factepoch.Timestamp::from_unix_millis(200L),
  )
  match explanation {
    Ok(report) => inspect(report.source().id().value(), content="chat-18")
    Err(_) => fail("explain should retain source episode")
  }
}
