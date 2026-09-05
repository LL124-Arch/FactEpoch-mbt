///|
fn bt_time(value : Int64) -> @factepoch.Timestamp {
  @factepoch.Timestamp::from_unix_millis(value)
}

///|
fn bt_recorded(
  seq : Int64,
  id : String,
  recorded_at : Int64,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "bitemporal-tests",
    seq,
    @factepoch.EventId::new(id),
    bt_time(recorded_at),
    event,
  )
}

///|
fn bt_apply(
  graph : @factepoch.MemoryGraph,
  events : Array[@factepoch.RecordedEvent],
) -> Unit {
  match graph.apply(events) {
    Ok(_) => ()
    Err(_) => abort("bitemporal fixture must apply")
  }
}

///|
fn bt_query(
  graph : @factepoch.MemoryGraph,
  valid_at : Int64,
  known_at : Int64,
  filter : @factepoch.FactFilter,
  limit? : Int = 100,
) -> Array[@factepoch.FactView] raise @factepoch.MemoryError {
  let query = @factepoch.FactQuery::new(
    bt_time(valid_at),
    bt_time(known_at),
    filter,
    limit~,
  )
  match graph.query(query) {
    Ok(facts) => facts
    Err(_) => abort("valid query must succeed")
  }
}

///|
test "query respects known-time activation and valid-time half-open bounds" {
  let group = @factepoch.GroupId::new("group-query")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-query"),
    group,
    "Ari preferred MoonBit during the trial.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("ari"),
    group,
    "Ari",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("preference-v1"),
    group,
    subject.id(),
    "  Prefers\tLANGUAGE  ",
    Literal("MoonBit"),
    "Ari preferred MoonBit",
    bt_time(100L),
    Some(bt_time(200L)),
    9_200,
    @factepoch.Provenance::new([episode.id()], [], Some("fixture")),
  )
  let graph = @factepoch.MemoryGraph::new()
  bt_apply(graph, [
    bt_recorded(1L, "episode", 300L, RecordEpisode(episode)),
    bt_recorded(2L, "entity", 300L, PutEntity(subject)),
    bt_recorded(3L, "fact", 400L, AssertFact(fact)),
  ])
  let filter = @factepoch.FactFilter::new(predicate="prefers  language")
  inspect(bt_query(graph, 100L, 399L, filter).length(), content="0")
  let at_activation = bt_query(graph, 100L, 400L, filter)
  inspect(at_activation.length(), content="1")
  inspect(at_activation[0].fact().predicate(), content="  Prefers\tLANGUAGE  ")
  inspect(at_activation[0].predicate_key(), content="prefers language")
  inspect(
    at_activation[0]
    .effective_valid_to()
    .map(timestamp => timestamp.to_unix_millis()) ==
    Some(200L),
    content="true",
  )
  inspect(at_activation[0].activation_event_id().value(), content="fact")
  inspect(
    at_activation[0].activation_recorded_at().to_unix_millis(),
    content="400",
  )
  inspect(bt_query(graph, 199L, 400L, filter).length(), content="1")
  inspect(bt_query(graph, 200L, 400L, filter).length(), content="0")
}

///|
test "predicate keys change only frozen ASCII case and whitespace" {
  let group = @factepoch.GroupId::new("predicate-profile")
  let subject = @factepoch.EntityId::new("predicate-subject")
  let key = @factepoch.FactSlot::new(
    group, subject, "\tÄ-Tag_Name\u{000b}\u{000c}\r\nValue ",
  )
  inspect(key.group_id() == group, content="true")
  inspect(key.subject() == subject, content="true")
  inspect(key.predicate_key(), content="Ä-tag_name value")
  let composed = @factepoch.FactSlot::new(group, subject, "É")
  let decomposed = @factepoch.FactSlot::new(group, subject, "E\u{0301}")
  inspect(composed.predicate_key(), content="É")
  inspect(decomposed.predicate_key(), content="é")
  inspect(
    composed.predicate_key() == decomposed.predicate_key(),
    content="false",
  )
  try @factepoch.FactFilter::new(predicate="\t\r\n ") catch {
    InvalidField(field, _) => inspect(field, content="predicate")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("whitespace-only filter predicate must fail")
  }
}

///|
test "query includes late facts and every activation at the known millisecond" {
  let group = @factepoch.GroupId::new("late-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("late-episode"),
    group,
    "Two notes arrived together after the event.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("late-subject"),
    group,
    "Late subject",
    "test",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let first = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("late-a"),
    group,
    subject.id(),
    "status",
    Literal("first"),
    "First late fact",
    bt_time(50L),
    None,
    8_000,
    provenance,
  )
  let second = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("late-b"),
    group,
    subject.id(),
    "status",
    Literal("second"),
    "Second late fact",
    bt_time(50L),
    None,
    8_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  bt_apply(graph, [
    bt_recorded(1L, "late-episode-event", 500L, RecordEpisode(episode)),
    bt_recorded(2L, "late-subject-event", 500L, PutEntity(subject)),
    bt_recorded(3L, "late-a-event", 600L, AssertFact(first)),
    bt_recorded(4L, "late-b-event", 600L, AssertFact(second)),
  ])
  inspect(
    bt_query(graph, 75L, 599L, @factepoch.FactFilter::all()).length(),
    content="0",
  )
  let visible = bt_query(
    graph,
    75L,
    600L,
    @factepoch.FactFilter::new(subject=subject.id()),
  )
  inspect(visible.length(), content="2")
  inspect(visible[0].fact().id().value(), content="late-a")
  inspect(visible[1].fact().id().value(), content="late-b")
}

///|
test "query combines group subject object and provenance filters" {
  let group_a = @factepoch.GroupId::new("filter-a")
  let group_b = @factepoch.GroupId::new("filter-b")
  let episode_a = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("filter-episode-a"),
    group_a,
    "Kai selected MoonBit.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let episode_b = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("filter-episode-b"),
    group_b,
    "Lee selected Rust.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject_a = @factepoch.Entity::new(
    @factepoch.EntityId::new("filter-subject-a"),
    group_a,
    "Kai",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let subject_b = @factepoch.Entity::new(
    @factepoch.EntityId::new("filter-subject-b"),
    group_b,
    "Lee",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let fact_a = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("filter-fact-a"),
    group_a,
    subject_a.id(),
    "Selected Tool",
    Literal("MoonBit"),
    "Kai selected MoonBit",
    bt_time(100L),
    None,
    9_000,
    @factepoch.Provenance::new([episode_a.id()], [], None),
  )
  let fact_b = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("filter-fact-b"),
    group_b,
    subject_b.id(),
    "selected tool",
    Literal("Rust"),
    "Lee selected Rust",
    bt_time(100L),
    None,
    9_000,
    @factepoch.Provenance::new([episode_b.id()], [], None),
  )
  let graph = @factepoch.MemoryGraph::new()
  bt_apply(graph, [
    bt_recorded(1L, "fa-episode", 200L, RecordEpisode(episode_a)),
    bt_recorded(2L, "fb-episode", 200L, RecordEpisode(episode_b)),
    bt_recorded(3L, "fa-subject", 200L, PutEntity(subject_a)),
    bt_recorded(4L, "fb-subject", 200L, PutEntity(subject_b)),
    bt_recorded(5L, "fa-fact", 200L, AssertFact(fact_a)),
    bt_recorded(6L, "fb-fact", 200L, AssertFact(fact_b)),
  ])
  let filter = @factepoch.FactFilter::new(
    group_id=group_a,
    subject=subject_a.id(),
    predicate=" SELECTED\r\nTOOL ",
    object=Literal("MoonBit"),
    provenance_episode=episode_a.id(),
  )
  let result = bt_query(graph, 100L, 200L, filter)
  inspect(result.length(), content="1")
  inspect(result[0].fact().id().value(), content="filter-fact-a")
}

///|
fn bt_sorted_graph(reverse : Bool) -> @factepoch.MemoryGraph raise {
  let group = @factepoch.GroupId::new("sort-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("sort-episode"),
    group,
    "Three candidate facts.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("sort-subject"),
    group,
    "Sort subject",
    "test",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let high_old = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("sort-z"),
    group,
    subject.id(),
    "rank",
    Literal("high-old"),
    "High score older",
    bt_time(100L),
    None,
    9_500,
    provenance,
  )
  let high_new_a = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("sort-a"),
    group,
    subject.id(),
    "rank",
    Literal("high-new-a"),
    "High score newer A",
    bt_time(200L),
    None,
    9_500,
    provenance,
  )
  let high_new_b = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("sort-b"),
    group,
    subject.id(),
    "rank",
    Literal("high-new-b"),
    "High score newer B",
    bt_time(200L),
    None,
    9_500,
    provenance,
  )
  let low_new = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("sort-low"),
    group,
    subject.id(),
    "rank",
    Literal("low-new"),
    "Lower score newest",
    bt_time(250L),
    None,
    7_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  let facts = if reverse {
    [low_new, high_old, high_new_b, high_new_a]
  } else {
    [high_new_a, low_new, high_old, high_new_b]
  }
  bt_apply(graph, [
    bt_recorded(1L, "sort-episode-event", 300L, RecordEpisode(episode)),
    bt_recorded(2L, "sort-subject-event", 300L, PutEntity(subject)),
    bt_recorded(3L, "sort-fact-1", 300L, AssertFact(facts[0])),
    bt_recorded(4L, "sort-fact-2", 300L, AssertFact(facts[1])),
    bt_recorded(5L, "sort-fact-3", 300L, AssertFact(facts[2])),
    bt_recorded(6L, "sort-fact-4", 300L, AssertFact(facts[3])),
  ])
  graph
}

///|
test "query order and limits do not depend on insertion order" {
  let forward = bt_sorted_graph(false)
  let reverse = bt_sorted_graph(true)
  let filter = @factepoch.FactFilter::new(predicate="rank")
  let expected = ["sort-a", "sort-b", "sort-z", "sort-low"]
  for graph in [forward, reverse] {
    let facts = bt_query(graph, 250L, 300L, filter)
    inspect(
      facts.map(view => view.fact().id().value()) == expected,
      content="true",
    )
    inspect(facts[0].score_basis_points(), content="9500")
    inspect(facts[2].score_basis_points(), content="9500")
    inspect(facts[3].score_basis_points(), content="7000")
    inspect(bt_query(graph, 250L, 300L, filter, limit=1).length(), content="1")
  }
  try
    @factepoch.FactQuery::new(bt_time(250L), bt_time(300L), filter, limit=0)
  catch {
    InvalidLimit(limit) => inspect(limit, content="0")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("zero query limit must fail")
  }
  try
    @factepoch.FactQuery::new(
      bt_time(250L),
      bt_time(300L),
      filter,
      limit=10_001,
    )
  catch {
    InvalidLimit(limit) => inspect(limit, content="10001")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("query limit above the public bound must fail")
  }
}

///|
test "query arrays are defensive and replay preserves the projection" {
  let graph = bt_sorted_graph(false)
  let filter = @factepoch.FactFilter::all()
  let first = bt_query(graph, 250L, 300L, filter)
  let replayed = match @factepoch.MemoryGraph::replay(graph.snapshot_events()) {
    Ok(value) => value
    Err(_) => abort("valid snapshot must replay")
  }
  let from_replay = bt_query(replayed, 250L, 300L, filter)
  inspect(first == from_replay, content="true")
  first.clear()
  inspect(bt_query(graph, 250L, 300L, filter).length(), content="4")
}

///|
fn bt_history_graph() -> @factepoch.MemoryGraph raise {
  let group = @factepoch.GroupId::new("history-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("history-episode"),
    group,
    "A preference was recorded twice.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("history-subject"),
    group,
    "History subject",
    "test",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let first = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("history-first"),
    group,
    subject.id(),
    "Prefers\tLanguage",
    Literal("MoonBit"),
    "First preference",
    bt_time(100L),
    Some(bt_time(200L)),
    8_000,
    provenance,
  )
  let second = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("history-second"),
    group,
    subject.id(),
    "prefers language",
    Literal("Rust"),
    "Second preference",
    bt_time(200L),
    None,
    9_000,
    provenance,
  )
  let unrelated = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("history-unrelated"),
    group,
    subject.id(),
    "owns",
    Literal("keyboard"),
    "Unrelated fact",
    bt_time(100L),
    None,
    10_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  bt_apply(graph, [
    bt_recorded(1L, "history-episode-event", 300L, RecordEpisode(episode)),
    bt_recorded(2L, "history-subject-event", 300L, PutEntity(subject)),
    bt_recorded(3L, "history-first-event", 400L, AssertFact(first)),
    bt_recorded(4L, "history-unrelated-event", 450L, AssertFact(unrelated)),
    bt_recorded(5L, "history-second-event", 500L, AssertFact(second)),
  ])
  graph
}

///|
fn bt_history(
  graph : @factepoch.MemoryGraph,
  query : @factepoch.HistoryQuery,
) -> Array[@factepoch.FactView] {
  match graph.history(query) {
    Ok(facts) => facts
    Err(_) => abort("valid history query must succeed")
  }
}

///|
test "history uses a closed knowledge window and normalized slot targets" {
  let graph = bt_history_graph()
  let slot = @factepoch.FactSlot::new(
    @factepoch.GroupId::new("history-group"),
    @factepoch.EntityId::new("history-subject"),
    "  PREFERS\r\nLANGUAGE ",
  )
  inspect(slot.predicate_key(), content="prefers language")
  let both = bt_history(
    graph,
    @factepoch.HistoryQuery::new(BySlot(slot), bt_time(400L), bt_time(500L)),
  )
  inspect(both.length(), content="2")
  inspect(both[0].fact().id().value(), content="history-second")
  inspect(both[1].fact().id().value(), content="history-first")
  let first_only = bt_history(
    graph,
    @factepoch.HistoryQuery::new(
      ByFactId(@factepoch.FactId::new("history-first")),
      bt_time(400L),
      bt_time(400L),
    ),
  )
  inspect(first_only.length(), content="1")
  inspect(
    first_only[0].activation_event_id().value(),
    content="history-first-event",
  )
  let after_first = bt_history(
    graph,
    @factepoch.HistoryQuery::new(BySlot(slot), bt_time(401L), bt_time(499L)),
  )
  inspect(after_first.length(), content="0")
}

///|
test "history validates ranges and limits and returns defensive arrays" {
  let graph = bt_history_graph()
  let target : @factepoch.HistoryTarget = ByFactId(
    @factepoch.FactId::new("history-first"),
  )
  try @factepoch.HistoryQuery::new(target, bt_time(501L), bt_time(500L)) catch {
    InvalidTimeRange(axis, _, _) => inspect(axis, content="history.known_at")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("reversed history window must fail")
  }
  try
    @factepoch.HistoryQuery::new(target, bt_time(400L), bt_time(500L), limit=0)
  catch {
    InvalidLimit(limit) => inspect(limit, content="0")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("zero history limit must fail")
  }
  let result = bt_history(
    graph,
    @factepoch.HistoryQuery::new(target, bt_time(400L), bt_time(500L)),
  )
  result.clear()
  inspect(
    bt_history(
      graph,
      @factepoch.HistoryQuery::new(target, bt_time(400L), bt_time(500L)),
    ).length(),
    content="1",
  )
}

///|
fn bt_diff(
  graph : @factepoch.MemoryGraph,
  query : @factepoch.DiffQuery,
) -> @factepoch.FactDiff {
  match graph.diff(query) {
    Ok(diff) => diff
    Err(_) => abort("valid diff query must succeed")
  }
}

///|
test "diff compares knowledge snapshots at one valid time" {
  let graph = bt_history_graph()
  let filter = @factepoch.FactFilter::new(predicate="prefers language")
  let diff = bt_diff(
    graph,
    @factepoch.DiffQuery::new(
      AcrossKnowledge(bt_time(250L), bt_time(400L), bt_time(500L)),
      filter,
    ),
  )
  inspect(diff.added().length(), content="1")
  inspect(diff.added()[0].fact().id().value(), content="history-second")
  inspect(diff.removed().length(), content="0")
  inspect(diff.unchanged().length(), content="0")
}

///|
test "diff compares valid-time snapshots and returns defensive partitions" {
  let graph = bt_history_graph()
  let diff = bt_diff(
    graph,
    @factepoch.DiffQuery::new(
      AcrossValidity(bt_time(500L), bt_time(150L), bt_time(250L)),
      @factepoch.FactFilter::all(),
    ),
  )
  inspect(diff.added().length(), content="1")
  inspect(diff.added()[0].fact().id().value(), content="history-second")
  inspect(diff.removed().length(), content="1")
  inspect(diff.removed()[0].fact().id().value(), content="history-first")
  inspect(diff.unchanged().length(), content="1")
  inspect(diff.unchanged()[0].fact().id().value(), content="history-unrelated")
  let added = diff.added()
  let removed = diff.removed()
  let unchanged = diff.unchanged()
  added.clear()
  removed.clear()
  unchanged.clear()
  inspect(diff.added().length(), content="1")
  inspect(diff.removed().length(), content="1")
  inspect(diff.unchanged().length(), content="1")
}

///|
test "diff rejects reversed knowledge and validity axes" {
  let filter = @factepoch.FactFilter::all()
  try
    @factepoch.DiffQuery::new(
      AcrossKnowledge(bt_time(100L), bt_time(300L), bt_time(200L)),
      filter,
    )
  catch {
    InvalidTimeRange(axis, _, _) => inspect(axis, content="diff.known_at")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("reversed knowledge diff must fail")
  }
  try
    @factepoch.DiffQuery::new(
      AcrossValidity(bt_time(300L), bt_time(200L), bt_time(100L)),
      filter,
    )
  catch {
    InvalidTimeRange(axis, _, _) => inspect(axis, content="diff.valid_at")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("reversed validity diff must fail")
  }
}
