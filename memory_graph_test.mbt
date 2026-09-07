// SPDX-License-Identifier: Apache-2.0

///|
fn envelope(
  seq : Int64,
  id : String,
  recorded_at : Int64,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "test-stream",
    seq,
    @factepoch.EventId::new(id),
    @factepoch.Timestamp::from_unix_millis(recorded_at),
    event,
  )
}

///|
test "a rejected batch leaves no valid prefix" {
  let group = @factepoch.GroupId::new("g")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("ep"),
    group,
    "source text",
  )
  let missing = @factepoch.EntityId::new("missing")
  let bad_fact = @factepoch.Fact::new(
    @factepoch.FactId::new("bad"),
    group,
    missing,
    "likes",
    Literal("tea"),
    "missing likes tea",
    @factepoch.Timestamp::from_unix_millis(10L),
    episode.id(),
  )
  let graph = @factepoch.MemoryGraph::new()
  let result = graph.apply([
    envelope(1L, "e1", 20L, RecordEpisode(episode)),
    envelope(2L, "e2", 21L, AssertFact(bad_fact)),
  ])
  inspect(result is Err(MissingEntity(_)), content="true")
  inspect(graph.event_count(), content="0")
}

///|
test "exact event replay is idempotent" {
  let group = @factepoch.GroupId::new("g")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("ep"),
    group,
    "source text",
  )
  let event = envelope(1L, "e1", 20L, RecordEpisode(episode))
  let graph = @factepoch.MemoryGraph::new()
  inspect(graph.apply([event]) is Ok(_), content="true")
  let replay = graph.apply([event])
  match replay {
    Ok(report) => {
      inspect(report.accepted().length(), content="0")
      inspect(report.idempotent().length(), content="1")
    }
    Err(_) => fail("exact replay should be idempotent")
  }
  inspect(graph.event_count(), content="1")
}
