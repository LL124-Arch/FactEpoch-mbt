///|
test "ranked candidates are normalized and fused deterministically" {
  let a = @factepoch.FactId::new("rank-a")
  let b = @factepoch.FactId::new("rank-b")
  let first = @factepoch.RankedCandidateList::new("bm25", [
    @factepoch.RankedCandidate::new(b, 1, Some(0.5)),
    @factepoch.RankedCandidate::new(a, 0, Some(0.9)),
  ])
  let second = @factepoch.RankedCandidateList::new("vector", [
    @factepoch.RankedCandidate::new(a, 1, None),
    @factepoch.RankedCandidate::new(b, 0, None),
  ])
  let fused = @factepoch.reciprocal_rank_fusion(
    [second, first],
    @factepoch.RrfConfig::new(1, 0.0),
  )
  inspect(fused.length(), content="2")
  inspect(fused[0].fact_id().value(), content="rank-a")
  inspect(fused[1].fact_id().value(), content="rank-b")
  inspect(fused[0].score().is_close(1.5), content="true")
  inspect(fused[0].contributions().length(), content="2")
}

///|
test "cosine follows the pinned zero-vector contract" {
  inspect(@factepoch.cosine_similarity([], []), content="0")
  inspect(@factepoch.cosine_similarity([0.0, 0.0], [1.0, 2.0]), content="0")
  inspect(@factepoch.cosine_similarity([1.0, 0.0], [0.0, 1.0]), content="0")
}

///|
test "neighbor query freezes the bounded traversal surface" {
  let query = @factepoch.NeighborQuery::new(
    @factepoch.EntityId::new("start"),
    @factepoch.Timestamp::from_unix_millis(10L),
    @factepoch.Timestamp::from_unix_millis(20L),
    0,
    Both,
    limit=10,
  )
  inspect(query.max_depth(), content="0")
}

///|
test "RRF validates rankings and is bit-stable under input permutations" {
  let a = @factepoch.FactId::new("stable-a")
  let b = @factepoch.FactId::new("stable-b")
  let left = @factepoch.RankedCandidateList::new("left", [
    @factepoch.RankedCandidate::new(b, 1, None),
    @factepoch.RankedCandidate::new(a, 0, Some(99.0)),
  ])
  let right = @factepoch.RankedCandidateList::new("right", [
    @factepoch.RankedCandidate::new(a, 1, None),
    @factepoch.RankedCandidate::new(b, 0, Some(-1.0)),
  ])
  let config = @factepoch.RrfConfig::new(1, 1.5)
  let forward = @factepoch.reciprocal_rank_fusion([left, right], config)
  let reversed = @factepoch.reciprocal_rank_fusion([right, left], config)
  inspect(forward.length(), content="2")
  inspect(
    forward.map(value => value.fact_id().value()).join(","),
    content="stable-a,stable-b",
  )
  inspect(
    forward[0].score().reinterpret_as_uint64() ==
    reversed[0].score().reinterpret_as_uint64(),
    content="true",
  )
  inspect(forward[0].score().is_close(1.5), content="true")
  let contributions = forward[0].contributions()
  inspect(contributions[0].source(), content="left")
  inspect(contributions[0].zero_based_rank(), content="0")
  contributions.clear()
  inspect(forward[0].contributions().length(), content="2")
  let returned = left.candidates()
  returned.clear()
  inspect(left.candidates().length(), content="2")
  try
    @factepoch.RankedCandidateList::new("duplicate-id", [
      @factepoch.RankedCandidate::new(a, 0, None),
      @factepoch.RankedCandidate::new(a, 1, None),
    ])
  catch {
    DuplicateRankedCandidate(id) => inspect(id == a, content="true")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate IDs must fail")
  }
  try
    @factepoch.RankedCandidateList::new("duplicate-rank", [
      @factepoch.RankedCandidate::new(a, 0, None),
      @factepoch.RankedCandidate::new(b, 0, None),
    ])
  catch {
    DuplicateCandidateRank(rank) => inspect(rank, content="0")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate ranks must fail")
  }
  try
    @factepoch.RankedCandidateList::new("gap", [
      @factepoch.RankedCandidate::new(a, 1, None),
    ])
  catch {
    InvalidCandidateRank(id, rank) => {
      inspect(id == a, content="true")
      inspect(rank, content="1")
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("rank gaps must fail")
  }
  try @factepoch.reciprocal_rank_fusion([left, left], config) catch {
    DuplicateRankSource => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate sources must fail")
  }
  try @factepoch.RrfConfig::new(0, 0.0) catch {
    InvalidRankConstant(value) => inspect(value, content="0")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("rank constant must be positive")
  }
  try @factepoch.RrfConfig::new(1, 0.0 / 0.0) catch {
    InvalidMinimumScore => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("minimum score must be finite")
  }
  try @factepoch.RankedCandidate::new(a, 0, Some(1.0 / 0.0)) catch {
    NonFiniteRankedScore(id) => inspect(id == a, content="true")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("source scores must be finite")
  }
  try @factepoch.RankedCandidateList::new(" \t ", []) catch {
    InvalidRankSource => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("blank ranking sources must fail")
  }
}

///|
test "cosine validates unsafe arithmetic without changing upstream values" {
  inspect(
    @factepoch.cosine_similarity([1.0, 2.0], [1.0, 2.0]).is_close(1.0),
    content="true",
  )
  inspect(
    @factepoch.cosine_similarity([1.0, 0.0], [-1.0, 0.0]).is_close(-1.0),
    content="true",
  )
  inspect(
    @factepoch.cosine_similarity([2.0, 0.0], [4.0, 0.0]).is_close(1.0),
    content="true",
  )
  try @factepoch.cosine_similarity([1.0], [1.0, 2.0]) catch {
    InvalidVectorDimensions(left, right) => {
      inspect(left, content="1")
      inspect(right, content="2")
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("dimension mismatch must fail")
  }
  try @factepoch.cosine_similarity([0.0 / 0.0], [1.0]) catch {
    NonFiniteVectorValue(LeftVector, index) => inspect(index, content="0")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("NaN must fail")
  }
  try @factepoch.cosine_similarity([1.0], [1.0 / 0.0]) catch {
    NonFiniteVectorValue(RightVector, index) => inspect(index, content="0")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("infinity must fail")
  }
  try @factepoch.cosine_similarity([1.0e308], [1.0e308]) catch {
    NonFiniteVectorComputation => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("overflow must fail")
  }
}

///|
fn retrieval_time(value : Int64) -> @factepoch.Timestamp {
  @factepoch.Timestamp::from_unix_millis(value)
}

///|
fn retrieval_event(
  seq : Int64,
  id : String,
  recorded : Int64,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "retrieval-stream",
    seq,
    @factepoch.EventId::new(id),
    retrieval_time(recorded),
    event,
  )
}

///|
fn apply_retrieval(
  graph : @factepoch.MemoryGraph,
  events : Array[@factepoch.RecordedEvent],
) -> Unit {
  match graph.apply(events) {
    Ok(_) => ()
    Err(_) => abort("retrieval fixture must apply")
  }
}

///|
test "query_ranked joins before limit and cannot bypass bitemporal visibility" {
  let group = @factepoch.GroupId::new("ranked-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("ranked-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("ranked-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let high = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("ranked-high"),
    group,
    subject.id(),
    "state",
    Literal("high"),
    "high",
    retrieval_time(100L),
    None,
    10_000,
    provenance,
  )
  let low = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("ranked-low"),
    group,
    subject.id(),
    "state",
    Literal("low"),
    "low",
    retrieval_time(200L),
    None,
    1_000,
    provenance,
  )
  let outside = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("ranked-outside"),
    group,
    subject.id(),
    "state",
    Literal("outside"),
    "outside",
    retrieval_time(100L),
    Some(retrieval_time(150L)),
    9_000,
    provenance,
  )
  let closed = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("ranked-closed"),
    group,
    subject.id(),
    "state",
    Literal("closed"),
    "closed",
    retrieval_time(100L),
    None,
    8_000,
    provenance,
  )
  let future = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("ranked-future"),
    group,
    subject.id(),
    "state",
    Literal("future"),
    "future",
    retrieval_time(100L),
    None,
    8_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  apply_retrieval(graph, [
    retrieval_event(1L, "ranked-episode-event", 300L, RecordEpisode(episode)),
    retrieval_event(2L, "ranked-subject-event", 300L, PutEntity(subject)),
    retrieval_event(3L, "ranked-high-event", 300L, AssertFact(high)),
    retrieval_event(4L, "ranked-low-event", 300L, AssertFact(low)),
    retrieval_event(5L, "ranked-outside-event", 300L, AssertFact(outside)),
    retrieval_event(6L, "ranked-closed-event", 300L, AssertFact(closed)),
    retrieval_event(
      7L,
      "ranked-close-event",
      400L,
      RetractFact(closed.id(), retrieval_time(200L), "closed"),
    ),
    retrieval_event(8L, "ranked-future-event", 500L, AssertFact(future)),
  ])
  let ordinary_query = @factepoch.FactQuery::new(
    retrieval_time(250L),
    retrieval_time(400L),
    @factepoch.FactFilter::all(),
    limit=1,
  )
  let ordinary = match graph.query(ordinary_query) {
    Ok(value) => value
    Err(_) => abort("ordinary query must work")
  }
  inspect(ordinary[0].fact().id() == high.id(), content="true")
  let ranking = @factepoch.RankedCandidateList::new("external", [
    @factepoch.RankedCandidate::new(low.id(), 0, None),
    @factepoch.RankedCandidate::new(high.id(), 1, None),
    @factepoch.RankedCandidate::new(outside.id(), 2, None),
    @factepoch.RankedCandidate::new(closed.id(), 3, None),
    @factepoch.RankedCandidate::new(future.id(), 4, None),
    @factepoch.RankedCandidate::new(
      @factepoch.FactId::new("ranked-unknown"),
      5,
      None,
    ),
  ])
  let fused = @factepoch.reciprocal_rank_fusion(
    [ranking],
    @factepoch.RrfConfig::default(),
  )
  let ranked = match graph.query_ranked(ordinary_query, fused) {
    Ok(value) => value
    Err(_) => abort("ranked query must work")
  }
  inspect(ranked.length(), content="1")
  inspect(ranked[0].view().fact().id() == low.id(), content="true")
  let contributions = ranked[0].contributions()
  contributions.clear()
  inspect(ranked[0].contributions().length(), content="1")
  match graph.query_ranked(ordinary_query, [fused[0], fused[0]]) {
    Err(DuplicateFusedCandidate(id)) => inspect(id == low.id(), content="true")
    _ => fail("duplicate fused IDs must fail")
  }
  let before_close = @factepoch.FactQuery::new(
    retrieval_time(250L),
    retrieval_time(399L),
    @factepoch.FactFilter::all(),
    limit=10,
  )
  let before = match graph.query_ranked(before_close, fused) {
    Ok(value) => value
    Err(_) => abort("pre-closure ranked query must work")
  }
  inspect(
    before
    .map(value => value.view().fact().id().value())
    .contains("ranked-closed"),
    content="true",
  )
  let after = match
    graph.query_ranked(
      @factepoch.FactQuery::new(
        retrieval_time(250L),
        retrieval_time(500L),
        @factepoch.FactFilter::all(),
        limit=10,
      ),
      fused,
    ) {
    Ok(value) => value
    Err(_) => abort("post-closure ranked query must work")
  }
  inspect(
    after.map(value => value.view().fact().id().value()).join(","),
    content="ranked-low,ranked-high,ranked-future",
  )
  let tied = @factepoch.reciprocal_rank_fusion(
    [
      @factepoch.RankedCandidateList::new("high-source", [
        @factepoch.RankedCandidate::new(high.id(), 0, None),
      ]),
      @factepoch.RankedCandidateList::new("low-source", [
        @factepoch.RankedCandidate::new(low.id(), 0, None),
      ]),
    ],
    @factepoch.RrfConfig::default(),
  )
  let tied_result = match
    graph.query_ranked(
      @factepoch.FactQuery::new(
        retrieval_time(250L),
        retrieval_time(400L),
        @factepoch.FactFilter::all(),
        limit=10,
      ),
      tied,
    ) {
    Ok(value) => value
    Err(_) => abort("tied ranked query must work")
  }
  inspect(
    tied_result.map(value => value.view().fact().id().value()).join(","),
    content="ranked-low,ranked-high",
  )
}

///|
test "bounded BFS keeps literal leaves directional and orders breadth first" {
  let group = @factepoch.GroupId::new("bfs-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("bfs-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let a = @factepoch.Entity::new(
    @factepoch.EntityId::new("bfs-a"),
    group,
    "A",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let b = @factepoch.Entity::new(
    @factepoch.EntityId::new("bfs-b"),
    group,
    "B",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let c = @factepoch.Entity::new(
    @factepoch.EntityId::new("bfs-c"),
    group,
    "C",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let d = @factepoch.Entity::new(
    @factepoch.EntityId::new("bfs-d"),
    group,
    "D",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let future_start = @factepoch.Entity::new(
    @factepoch.EntityId::new("bfs-future"),
    group,
    "Future",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let literal = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-literal"),
    group,
    a.id(),
    "note",
    Literal("leaf"),
    "leaf",
    retrieval_time(100L),
    None,
    9_000,
    provenance,
  )
  let ab = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-ab"),
    group,
    a.id(),
    "link",
    EntityRef(b.id()),
    "a to b",
    retrieval_time(100L),
    None,
    1_000,
    provenance,
  )
  let ac = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-ac"),
    group,
    a.id(),
    "link",
    EntityRef(c.id()),
    "a to c",
    retrieval_time(200L),
    None,
    8_000,
    provenance,
  )
  let bd = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-bd"),
    group,
    b.id(),
    "link",
    EntityRef(d.id()),
    "b to d",
    retrieval_time(100L),
    None,
    10_000,
    provenance,
  )
  let cd = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-cd"),
    group,
    c.id(),
    "blocked",
    EntityRef(d.id()),
    "c to d",
    retrieval_time(100L),
    None,
    10_000,
    provenance,
  )
  let self_loop = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-self"),
    group,
    a.id(),
    "link",
    EntityRef(a.id()),
    "a to a",
    retrieval_time(100L),
    None,
    5_000,
    provenance,
  )
  let replace_old = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-replace-old"),
    group,
    d.id(),
    "replace",
    EntityRef(b.id()),
    "old",
    retrieval_time(100L),
    None,
    6_000,
    provenance,
  )
  let replace_new = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-replace-new"),
    group,
    d.id(),
    "replace",
    EntityRef(b.id()),
    "new",
    retrieval_time(300L),
    None,
    7_000,
    provenance,
  )
  let late_edge = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("bfs-late-edge"),
    group,
    d.id(),
    "late",
    EntityRef(future_start.id()),
    "late",
    retrieval_time(100L),
    None,
    7_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  apply_retrieval(graph, [
    retrieval_event(1L, "bfs-episode-event", 300L, RecordEpisode(episode)),
    retrieval_event(2L, "bfs-a-event", 300L, PutEntity(a)),
    retrieval_event(3L, "bfs-b-event", 300L, PutEntity(b)),
    retrieval_event(4L, "bfs-c-event", 300L, PutEntity(c)),
    retrieval_event(5L, "bfs-d-event", 300L, PutEntity(d)),
    retrieval_event(6L, "bfs-literal-event", 300L, AssertFact(literal)),
    retrieval_event(7L, "bfs-ab-event", 300L, AssertFact(ab)),
    retrieval_event(8L, "bfs-ac-event", 300L, AssertFact(ac)),
    retrieval_event(9L, "bfs-bd-event", 300L, AssertFact(bd)),
    retrieval_event(10L, "bfs-cd-event", 300L, AssertFact(cd)),
    retrieval_event(11L, "bfs-self-event", 300L, AssertFact(self_loop)),
    retrieval_event(12L, "bfs-replace-old-event", 300L, AssertFact(replace_old)),
    retrieval_event(
      13L,
      "bfs-future-entity-event",
      500L,
      PutEntity(future_start),
    ),
    retrieval_event(14L, "bfs-late-edge-event", 500L, AssertFact(late_edge)),
    retrieval_event(
      15L,
      "bfs-late-retract-event",
      600L,
      RetractFact(late_edge.id(), retrieval_time(200L), "removed"),
    ),
    retrieval_event(
      16L,
      "bfs-replace-event",
      700L,
      SupersedeFact(
        replace_new,
        [replace_old.id()],
        @factepoch.ConflictDecision::new(
          "maintainer",
          "replacement",
          replace_new.id(),
          [replace_old.id()],
          SupersedeExisting,
        ),
      ),
    ),
  ])
  let outgoing = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        2,
        Outgoing,
        limit=10,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("outgoing traversal must work")
  }
  inspect(
    outgoing.map(value => value.view().fact().id().value()).join(","),
    content="bfs-literal,bfs-ac,bfs-self,bfs-ab,bfs-bd,bfs-cd",
  )
  outgoing.clear()
  let outgoing_again = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        2,
        Outgoing,
        limit=10,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("repeated outgoing traversal must work")
  }
  inspect(outgoing_again.length(), content="6")
  inspect(outgoing_again[0].depth(), content="1")
  inspect(outgoing_again[3].depth(), content="1")
  inspect(outgoing_again[4].depth(), content="2")
  inspect(outgoing_again[5].depth(), content="2")
  inspect(outgoing_again[3].view().fact().id() == ab.id(), content="true")
  inspect(outgoing_again[4].view().fact().id() == bd.id(), content="true")
  let incoming = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        1,
        Incoming,
        limit=10,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("incoming traversal must work")
  }
  inspect(
    incoming.map(value => value.view().fact().id().value()).join(","),
    content="bfs-self",
  )
  let filtered = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        2,
        Outgoing,
        predicate="link",
        limit=10,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("filtered traversal must work")
  }
  inspect(
    filtered.map(value => value.view().fact().id().value()).join(","),
    content="bfs-ac,bfs-self,bfs-ab,bfs-bd",
  )
  let wrong_group = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        2,
        Outgoing,
        group_id=@factepoch.GroupId::new("another-group"),
        limit=10,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("group-filtered traversal must work")
  }
  inspect(wrong_group.length(), content="0")
  let limited = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        2,
        Both,
        limit=2,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("limited traversal must work")
  }
  inspect(
    limited.map(value => value.view().fact().id().value()).join(","),
    content="bfs-literal,bfs-ac",
  )
  let zero = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        a.id(),
        retrieval_time(250L),
        retrieval_time(400L),
        0,
        Both,
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("zero-depth known start must work")
  }
  inspect(zero.length(), content="0")
  match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        future_start.id(),
        retrieval_time(250L),
        retrieval_time(499L),
        0,
        Both,
      ),
    ) {
    Err(MissingEntity(id)) => inspect(id == future_start.id(), content="true")
    _ => fail("future start must be missing")
  }
  match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        @factepoch.EntityId::new("bfs-missing"),
        retrieval_time(250L),
        retrieval_time(600L),
        1,
        Both,
      ),
    ) {
    Err(MissingEntity(id)) => inspect(id.value(), content="bfs-missing")
    _ => fail("unknown start must be missing")
  }
  let late_before = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        d.id(),
        retrieval_time(250L),
        retrieval_time(499L),
        1,
        Outgoing,
        predicate="late",
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("late-before traversal must work")
  }
  inspect(late_before.length(), content="0")
  let late_known = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        d.id(),
        retrieval_time(250L),
        retrieval_time(500L),
        1,
        Outgoing,
        predicate="late",
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("late-known traversal must work")
  }
  inspect(late_known.length(), content="1")
  let late_closed = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        d.id(),
        retrieval_time(250L),
        retrieval_time(600L),
        1,
        Outgoing,
        predicate="late",
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("late-closed traversal must work")
  }
  inspect(late_closed.length(), content="0")
  let before_supersede = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        d.id(),
        retrieval_time(350L),
        retrieval_time(699L),
        1,
        Outgoing,
        predicate="replace",
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("pre-supersession traversal must work")
  }
  inspect(
    before_supersede[0].view().fact().id() == replace_old.id(),
    content="true",
  )
  let at_supersede = match
    graph.neighbors(
      @factepoch.NeighborQuery::new(
        d.id(),
        retrieval_time(300L),
        retrieval_time(700L),
        1,
        Outgoing,
        predicate="replace",
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("post-supersession traversal must work")
  }
  inspect(
    at_supersede[0].view().fact().id() == replace_new.id(),
    content="true",
  )
  try
    @factepoch.NeighborQuery::new(
      a.id(),
      retrieval_time(250L),
      retrieval_time(400L),
      65,
      Both,
    )
  catch {
    InvalidNeighborDepth(value) => inspect(value, content="65")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("depth must be bounded")
  }
}
