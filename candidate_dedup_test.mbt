///|
fn entity_candidate(
  id : String,
  group : String,
  subject : String,
  object : String,
  predicate : String,
  statement : String,
  confidence : Int,
  episodes : Array[String],
) -> @factepoch.CandidateFact raise @factepoch.MemoryError {
  @factepoch.CandidateFact::new(
    @factepoch.CandidateId::new(id),
    @factepoch.GroupId::new(group),
    @factepoch.EntityId::new(subject),
    predicate,
    EntityRef(@factepoch.EntityId::new(object)),
    statement,
    confidence,
    episodes.map(episode => @factepoch.EpisodeId::new(episode)),
  )
}

///|
fn literal_candidate(
  id : String,
  value : String,
  statement : String,
) -> @factepoch.CandidateFact raise @factepoch.MemoryError {
  @factepoch.CandidateFact::new(
    @factepoch.CandidateId::new(id),
    @factepoch.GroupId::new("group-a"),
    @factepoch.EntityId::new("subject-a"),
    "has value",
    Literal(value),
    statement,
    7_500,
    [@factepoch.EpisodeId::new("episode-a")],
  )
}

///|
test "candidate values validate and defensively own episode references" {
  inspect(
    @factepoch.CandidateId::new("candidate-a").value(),
    content="candidate-a",
  )
  try @factepoch.CandidateId::new("") catch {
    InvalidIdentifier(kind, _) => inspect(kind, content="CandidateId")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty candidate ID must fail")
  }
  let input = [
    @factepoch.EpisodeId::new("episode-b"),
    @factepoch.EpisodeId::new("episode-a"),
    @factepoch.EpisodeId::new("episode-a"),
  ]
  let candidate = @factepoch.CandidateFact::new(
    @factepoch.CandidateId::new("candidate-a"),
    @factepoch.GroupId::new("group-a"),
    @factepoch.EntityId::new("subject-a"),
    " raw predicate ",
    EntityRef(@factepoch.EntityId::new("object-a")),
    "Raw statement",
    7_500,
    input,
  )
  input.clear()
  inspect(candidate.candidate_id().value(), content="candidate-a")
  inspect(candidate.group_id().value(), content="group-a")
  inspect(candidate.subject().value(), content="subject-a")
  inspect(candidate.predicate(), content=" raw predicate ")
  inspect(candidate.statement(), content="Raw statement")
  inspect(candidate.confidence_basis_points(), content="7500")
  let episodes = candidate.episode_ids()
  inspect(episodes.length(), content="2")
  inspect(episodes[0].value(), content="episode-a")
  inspect(episodes[1].value(), content="episode-b")
  episodes.clear()
  inspect(candidate.episode_ids().length(), content="2")
  match candidate.object() {
    EntityRef(id) => inspect(id.value(), content="object-a")
    Literal(_) => fail("expected entity reference")
  }
}

///|
test "candidate validation rejects empty text literals sources and bad confidence" {
  try
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "",
      "fact",
      1,
      ["episode-a"],
    )
  catch {
    InvalidField(field, _) => inspect(field, content="predicate")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty predicate must fail")
  }
  try
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "p",
      "",
      1,
      ["episode-a"],
    )
  catch {
    InvalidField(field, _) => inspect(field, content="statement")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty statement must fail")
  }
  try literal_candidate("candidate-a", "", "fact") catch {
    InvalidField(field, _) => inspect(field, content="object.literal")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty literal must fail")
  }
  try
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "p",
      "fact",
      10_001,
      ["episode-a"],
    )
  catch {
    InvalidConfidence(value) => inspect(value, content="10001")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("out-of-range confidence must fail")
  }
  try
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "p",
      "fact",
      -1,
      ["episode-a"],
    )
  catch {
    InvalidConfidence(value) => inspect(value, content="-1")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("negative confidence must fail")
  }
  try
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "p",
      "fact",
      1,
      [],
    )
  catch {
    InvalidField(field, _) => inspect(field, content="episode_ids")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("candidate without an episode must fail")
  }
}

///|
test "entity dedup key is directed and explicitly group scoped" {
  let report = @factepoch.deduplicate_candidates([
    entity_candidate("forward-a", "group-a", "a", "b", "p", "same", 1, [
      "episode-a",
    ]),
    entity_candidate("reverse-a", "group-a", "b", "a", "p", "same", 1, [
      "episode-a",
    ]),
    entity_candidate("forward-b", "group-b", "a", "b", "p", "same", 1, [
      "episode-a",
    ]),
  ])
  inspect(report.input_count(), content="3")
  inspect(report.output_count(), content="3")
  inspect(report.collapsed_count(), content="0")
  for value in report.candidates() {
    let kinds = value.parity_kinds()
    inspect(kinds.length(), content="2")
    inspect(kinds[0] == ExactUpstream, content="true")
    inspect(kinds[1] == DocumentedAdaptation, content="true")
  }
}

///|
test "same Graphiti key keeps first fields and unions provenance as adaptation" {
  let first = entity_candidate(
    "candidate-first",
    "group-a",
    "subject-a",
    "object-a",
    "first predicate",
    "  SAME\tFACT ",
    2_000,
    ["episode-c", "episode-a"],
  )
  let second = entity_candidate(
    "candidate-second",
    "group-a",
    "subject-a",
    "object-a",
    "different predicate",
    "same fact",
    9_000,
    ["episode-b"],
  )
  let report = @factepoch.deduplicate_candidates([first, second])
  inspect(report.input_count(), content="2")
  inspect(report.output_count(), content="1")
  inspect(report.collapsed_count(), content="1")
  let value = report.candidates()[0]
  inspect(
    value.retained_candidate().candidate_id().value(),
    content="candidate-first",
  )
  inspect(value.retained_candidate().predicate(), content="first predicate")
  inspect(value.retained_candidate().confidence_basis_points(), content="2000")
  inspect(
    value.member_candidate_ids().map(id => id.value()).join(","),
    content="candidate-first,candidate-second",
  )
  inspect(
    value.episode_ids().map(id => id.value()).join(","),
    content="episode-a,episode-b,episode-c",
  )
  let kinds = value.parity_kinds()
  inspect(kinds.length(), content="2")
  inspect(kinds[0] == ExactUpstream, content="true")
  inspect(kinds[1] == DocumentedAdaptation, content="true")
}

///|
test "input permutation changes only first retention and encounter-order members" {
  let first = entity_candidate(
    "candidate-first",
    "group-a",
    "subject-a",
    "object-a",
    "p1",
    "same",
    1,
    ["episode-b"],
  )
  let second = entity_candidate(
    "candidate-second",
    "group-a",
    "subject-a",
    "object-a",
    "p2",
    "SAME",
    2,
    ["episode-a"],
  )
  let forward = @factepoch.deduplicate_candidates([first, second]).candidates()[0]
  let reverse = @factepoch.deduplicate_candidates([second, first]).candidates()[0]
  inspect(
    forward.retained_candidate().candidate_id().value(),
    content="candidate-first",
  )
  inspect(
    reverse.retained_candidate().candidate_id().value(),
    content="candidate-second",
  )
  inspect(
    forward.member_candidate_ids().map(id => id.value()).join(","),
    content="candidate-first,candidate-second",
  )
  inspect(
    reverse.member_candidate_ids().map(id => id.value()).join(","),
    content="candidate-second,candidate-first",
  )
  inspect(
    forward.episode_ids().map(id => id.value()).join(","),
    content="episode-a,episode-b",
  )
  inspect(
    reverse.episode_ids().map(id => id.value()).join(","),
    content="episode-a,episode-b",
  )
}

///|
test "literal candidates pass through individually as documented adaptations" {
  let report = @factepoch.deduplicate_candidates([
    literal_candidate("literal-a", "blue", "same"),
    literal_candidate("literal-b", "blue", "SAME"),
  ])
  inspect(report.output_count(), content="2")
  inspect(report.collapsed_count(), content="0")
  for value in report.candidates() {
    inspect(value.member_candidate_ids().length(), content="1")
    let kinds = value.parity_kinds()
    inspect(kinds.length(), content="1")
    inspect(kinds[0] == DocumentedAdaptation, content="true")
  }
}

///|
test "batch rejects duplicate candidate IDs before returning a report" {
  let first = entity_candidate(
    "duplicate",
    "group-a",
    "subject-a",
    "object-a",
    "p",
    "one",
    1,
    ["episode-a"],
  )
  let second = literal_candidate("duplicate", "two", "two")
  try @factepoch.deduplicate_candidates([first, second]) catch {
    DuplicateCandidateId(id) => inspect(id.value(), content="duplicate")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("duplicate candidate ID must fail")
  }
}

///|
test "dedup result collections are defensive copies" {
  let report = @factepoch.deduplicate_candidates([
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "p",
      "same",
      1,
      ["episode-a"],
    ),
  ])
  let values = report.candidates()
  let retained = values[0]
  values.clear()
  inspect(report.candidates().length(), content="1")
  let members = retained.member_candidate_ids()
  let episodes = retained.episode_ids()
  members.clear()
  episodes.clear()
  inspect(retained.member_candidate_ids().length(), content="1")
  inspect(retained.episode_ids().length(), content="1")
  let parity = retained.parity_kinds()
  inspect(parity.length(), content="2")
  inspect(parity[0] == ExactUpstream, content="true")
  inspect(parity[1] == DocumentedAdaptation, content="true")
  parity.clear()
  inspect(retained.parity_kinds().length(), content="2")
}

///|
test "materialize uses aggregated provenance and validates evidence membership" {
  let report = @factepoch.deduplicate_candidates([
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "p",
      "same",
      4_000,
      ["episode-a"],
    ),
    entity_candidate(
      "candidate-b",
      "group-a",
      "subject-a",
      "object-a",
      "other",
      "SAME",
      9_000,
      ["episode-b"],
    ),
  ])
  let value = report.candidates()[0]
  let evidence = @factepoch.EvidenceSpan::new(
    @factepoch.EpisodeId::new("episode-b"),
    0,
    1,
    None,
  )
  let fact = value.materialize(
    @factepoch.FactId::new("fact-a"),
    @factepoch.Timestamp::from_unix_millis(1_000L),
    None,
    [evidence],
    Some("fixture-v1"),
  )
  inspect(fact.id().value(), content="fact-a")
  inspect(fact.predicate(), content="p")
  inspect(fact.confidence_basis_points(), content="4000")
  inspect(
    fact.provenance().episode_ids().map(id => id.value()).join(","),
    content="episode-a,episode-b",
  )
  try
    value.materialize(
      @factepoch.FactId::new("fact-invalid"),
      @factepoch.Timestamp::from_unix_millis(1_000L),
      None,
      [
        @factepoch.EvidenceSpan::new(
          @factepoch.EpisodeId::new("episode-foreign"),
          0,
          1,
          None,
        ),
      ],
      None,
    )
  catch {
    InvalidEvidence(_) => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("foreign evidence episode must fail")
  }
}

///|
test "materialization allocates no identity and never merges formal fact IDs" {
  let value = @factepoch.deduplicate_candidates([
      entity_candidate(
        "candidate-a",
        "group-a",
        "subject-a",
        "object-a",
        "p",
        "same",
        1,
        ["episode-a"],
      ),
    ]).candidates()[0]
  let first = value.materialize(
    @factepoch.FactId::new("fact-a"),
    @factepoch.Timestamp::from_unix_millis(1_000L),
    None,
    [],
    None,
  )
  let second = value.materialize(
    @factepoch.FactId::new("fact-b"),
    @factepoch.Timestamp::from_unix_millis(1_000L),
    None,
    [],
    None,
  )
  inspect(first.id().value(), content="fact-a")
  inspect(second.id().value(), content="fact-b")
  inspect(first == second, content="false")
}

///|
fn candidate_recorded(
  seq : Int64,
  id : String,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "candidate-integration",
    seq,
    @factepoch.EventId::new(id),
    @factepoch.Timestamp::from_unix_millis(2_000L + seq),
    event,
  )
}

///|
fn candidate_materialized(
  evidence : Array[@factepoch.EvidenceSpan],
) -> @factepoch.FactAssertion raise @factepoch.MemoryError {
  @factepoch.deduplicate_candidates([
    entity_candidate(
      "candidate-a",
      "group-a",
      "subject-a",
      "object-a",
      "uses",
      "Subject uses object",
      8_000,
      ["episode-a"],
    ),
    entity_candidate(
      "candidate-b",
      "group-a",
      "subject-a",
      "object-a",
      "related",
      "SUBJECT  USES OBJECT",
      9_000,
      ["episode-b"],
    ),
  ]).candidates()[0].materialize(
    @factepoch.FactId::new("fact-integrated"),
    @factepoch.Timestamp::from_unix_millis(1_000L),
    None,
    evidence,
    Some("fixture-v1"),
  )
}

///|
fn candidate_entity(id : String, name : String) -> @factepoch.Entity raise {
  @factepoch.Entity::new(
    @factepoch.EntityId::new(id),
    @factepoch.GroupId::new("group-a"),
    name,
    "fixture",
    None,
    @factepoch.Metadata::empty(),
  )
}

///|
test "materialized candidates apply query and explain every source episode" {
  let group = @factepoch.GroupId::new("group-a")
  let episode_a = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-a"),
    group,
    "A",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let episode_b = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-b"),
    group,
    "B",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let fact = candidate_materialized([
    @factepoch.EvidenceSpan::new(episode_b.id(), 0, 1, None),
  ])
  let graph = @factepoch.MemoryGraph::new()
  match
    graph.apply([
      candidate_recorded(1L, "event-episode-a", RecordEpisode(episode_a)),
      candidate_recorded(2L, "event-episode-b", RecordEpisode(episode_b)),
      candidate_recorded(
        3L,
        "event-subject",
        PutEntity(candidate_entity("subject-a", "Subject")),
      ),
      candidate_recorded(
        4L,
        "event-object",
        PutEntity(candidate_entity("object-a", "Object")),
      ),
      candidate_recorded(5L, "event-fact", AssertFact(fact)),
    ]) {
    Ok(_) => ()
    Err(_) => fail("candidate integration fixture must apply")
  }
  let query = @factepoch.FactQuery::new(
    @factepoch.Timestamp::from_unix_millis(1_500L),
    @factepoch.Timestamp::from_unix_millis(3_000L),
    @factepoch.FactFilter::all(),
    limit=10,
  )
  match graph.query(query) {
    Ok(views) => {
      inspect(views.length(), content="1")
      inspect(views[0].fact().id().value(), content="fact-integrated")
    }
    Err(_) => fail("materialized fact must be queryable")
  }
  match
    graph.explain(
      fact.id(),
      @factepoch.Timestamp::from_unix_millis(1_500L),
      @factepoch.Timestamp::from_unix_millis(3_000L),
    ) {
    Ok(report) => {
      let sources = report.source_episodes()
      inspect(sources.length(), content="2")
      inspect(sources[0].id().value(), content="episode-a")
      inspect(sources[1].id().value(), content="episode-b")
    }
    Err(_) => fail("materialized fact must retain explainable sources")
  }
}

///|
test "apply rejects a materialized candidate with a missing source episode" {
  let group = @factepoch.GroupId::new("group-a")
  let episode_a = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-a"),
    group,
    "A",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let graph = @factepoch.MemoryGraph::new()
  match
    graph.apply([
      candidate_recorded(1L, "event-episode-a", RecordEpisode(episode_a)),
      candidate_recorded(
        2L,
        "event-subject",
        PutEntity(candidate_entity("subject-a", "Subject")),
      ),
      candidate_recorded(
        3L,
        "event-object",
        PutEntity(candidate_entity("object-a", "Object")),
      ),
      candidate_recorded(
        4L,
        "event-fact",
        AssertFact(candidate_materialized([])),
      ),
    ]) {
    Err(MissingEpisode(id)) => inspect(id.value(), content="episode-b")
    _ => fail("missing aggregated source must fail during apply")
  }
}

///|
test "apply validates source group and evidence body after materialization" {
  let group_a = @factepoch.GroupId::new("group-a")
  let group_b = @factepoch.GroupId::new("group-b")
  let episode_a = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-a"),
    group_a,
    "A",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let episode_b_wrong_group = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-b"),
    group_b,
    "B",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let wrong_group_graph = @factepoch.MemoryGraph::new()
  match
    wrong_group_graph.apply([
      candidate_recorded(1L, "wrong-episode-a", RecordEpisode(episode_a)),
      candidate_recorded(
        2L,
        "wrong-episode-b",
        RecordEpisode(episode_b_wrong_group),
      ),
      candidate_recorded(
        3L,
        "wrong-subject",
        PutEntity(candidate_entity("subject-a", "Subject")),
      ),
      candidate_recorded(
        4L,
        "wrong-object",
        PutEntity(candidate_entity("object-a", "Object")),
      ),
      candidate_recorded(
        5L,
        "wrong-fact",
        AssertFact(candidate_materialized([])),
      ),
    ]) {
    Err(GroupMismatch(ProvenanceReference(id))) =>
      inspect(id.value(), content="episode-b")
    _ => fail("wrong-group source must fail during apply")
  }

  let episode_a_again = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-a"),
    group_a,
    "A",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let episode_b = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("episode-b"),
    group_a,
    "B",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let invalid_evidence = @factepoch.EvidenceSpan::new(
    episode_b.id(),
    0,
    2,
    None,
  )
  let evidence_graph = @factepoch.MemoryGraph::new()
  match
    evidence_graph.apply([
      candidate_recorded(
        1L,
        "evidence-episode-a",
        RecordEpisode(episode_a_again),
      ),
      candidate_recorded(2L, "evidence-episode-b", RecordEpisode(episode_b)),
      candidate_recorded(
        3L,
        "evidence-subject",
        PutEntity(candidate_entity("subject-a", "Subject")),
      ),
      candidate_recorded(
        4L,
        "evidence-object",
        PutEntity(candidate_entity("object-a", "Object")),
      ),
      candidate_recorded(
        5L,
        "evidence-fact",
        AssertFact(candidate_materialized([invalid_evidence])),
      ),
    ]) {
    Err(InvalidEvidence(_)) => ()
    _ => fail("out-of-body evidence must fail during apply")
  }
}
