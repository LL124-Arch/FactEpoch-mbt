// SPDX-License-Identifier: Apache-2.0

///|
fn stamp(
  seq : Int64,
  id : String,
  at : Int64,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "preference-demo",
    seq,
    @factepoch.EventId::new(id),
    @factepoch.Timestamp::from_unix_millis(at),
    event,
  )
}

///|
fn answer(
  graph : @factepoch.MemoryGraph,
  group : @factepoch.GroupId,
  user : @factepoch.EntityId,
  known_at : Int64,
) -> String raise @factepoch.MemoryError {
  let query = @factepoch.FactQuery::new(
    @factepoch.Timestamp::from_unix_millis(160L),
    @factepoch.Timestamp::from_unix_millis(known_at),
    group,
    user,
    "prefers_drink",
  )
  match graph.query(query) {
    Ok([view]) =>
      match view.fact().object() {
        Literal(value) => value
        EntityRef(_) => "unexpected entity"
      }
    Ok(_) => "no unique answer"
    Err(_) => "query failed"
  }
}

///|
fn main {
  try {
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
      "Mira switched to coffee last week",
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
    ignore(
      graph.apply([
        stamp(1L, "episode-old", 110L, RecordEpisode(old_ep)),
        stamp(2L, "user", 111L, PutEntity(user)),
        stamp(3L, "fact-tea", 120L, AssertFact(tea)),
        stamp(4L, "episode-new", 180L, RecordEpisode(new_ep)),
        stamp(5L, "fact-coffee", 181L, SupersedeFact(coffee, [tea.id()])),
      ]),
    )
    println(
      "valid_at=160, known_at=140 -> " + answer(graph, group, user_id, 140L),
    )
    println(
      "valid_at=160, known_at=200 -> " + answer(graph, group, user_id, 200L),
    )
  } catch {
    _ => abort("preference_shift failed")
  }
}
