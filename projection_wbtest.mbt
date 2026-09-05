///|
test "known-time projection replays a closed event prefix" {
  let group = GroupId::new("projection-prefix")
  let episode = (id : String) => {
    Episode::new(
      EpisodeId::new(id),
      group,
      "Projection fixture \{id}",
      None,
      None,
      None,
      Metadata::empty(),
    )
  }
  let event = (seq : Int64, at : Int64, id : String) => {
    RecordedEvent::new(
      "projection-prefix",
      seq,
      EventId::new("event-\{id}"),
      Timestamp::from_unix_millis(at),
      RecordEpisode(episode(id)),
    )
  }
  let graph = MemoryGraph::new()
  match
    graph.apply([
      event(1L, 100L, "one"),
      event(2L, 200L, "two"),
      event(3L, 200L, "three"),
      event(4L, 300L, "future"),
    ]) {
    Ok(_) => ()
    Err(_) => fail("fixture must apply")
  }
  match project_at_known(graph, Timestamp::from_unix_millis(200L)) {
    Ok(projected) => {
      let events = projected.snapshot_events()
      inspect(events.length(), content="3")
      inspect(events[0].event_id().value(), content="event-one")
      inspect(events[1].event_id().value(), content="event-two")
      inspect(events[2].event_id().value(), content="event-three")
    }
    Err(_) => fail("valid prefix must replay")
  }
}
