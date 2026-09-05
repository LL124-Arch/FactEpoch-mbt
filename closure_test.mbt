///|
fn closure_time(value : Int64) -> @factepoch.Timestamp {
  @factepoch.Timestamp::from_unix_millis(value)
}

///|
test "conflict decisions own a sorted unique prior fact set" {
  let candidate = @factepoch.FactId::new("candidate")
  let prior = [@factepoch.FactId::new("old-b"), @factepoch.FactId::new("old-a")]
  let decision = @factepoch.ConflictDecision::new(
    "maintainer",
    "preference changed",
    candidate,
    prior,
    SupersedeExisting,
  )
  prior.clear()
  inspect(decision.actor(), content="maintainer")
  inspect(decision.rationale(), content="preference changed")
  inspect(decision.candidate_fact_id() == candidate, content="true")
  inspect(decision.action() == SupersedeExisting, content="true")
  let returned = decision.prior_fact_ids()
  inspect(returned.length(), content="2")
  inspect(returned[0].value(), content="old-a")
  inspect(returned[1].value(), content="old-b")
  returned.clear()
  inspect(decision.prior_fact_ids().length(), content="2")
  try
    @factepoch.ConflictDecision::new(
      "maintainer",
      "duplicate",
      candidate,
      [@factepoch.FactId::new("same"), @factepoch.FactId::new("same")],
      SupersedeExisting,
    )
  catch {
    DuplicateFactReference(id) => inspect(id.value(), content="same")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("duplicate prior IDs must fail")
  }
  try
    @factepoch.ConflictDecision::new(
      "maintainer",
      "self",
      candidate,
      [candidate],
      SupersedeExisting,
    )
  catch {
    ConflictDecisionMismatch(field) =>
      inspect(field, content="candidate_in_prior")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("candidate cannot be a prior fact")
  }
  try
    @factepoch.ConflictDecision::new(
      "maintainer",
      "empty",
      candidate,
      [],
      SupersedeExisting,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="prior_fact_ids")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty prior set must fail")
  }
  try
    @factepoch.ConflictDecision::new(
      "",
      "rationale",
      candidate,
      [@factepoch.FactId::new("old")],
      SupersedeExisting,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="actor")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty actor must fail")
  }
  try
    @factepoch.ConflictDecision::new(
      "actor",
      "",
      candidate,
      [@factepoch.FactId::new("old")],
      SupersedeExisting,
    )
  catch {
    InvalidField(field, _) => inspect(field, content="rationale")
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("empty rationale must fail")
  }
}

///|
test "recorded supersession payloads are canonical defensive values" {
  let group = @factepoch.GroupId::new("payload-group")
  let episode_id = @factepoch.EpisodeId::new("payload-episode")
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("payload-candidate"),
    group,
    @factepoch.EntityId::new("payload-subject"),
    "status",
    Literal("new"),
    "Payload candidate",
    closure_time(200L),
    None,
    9_000,
    @factepoch.Provenance::new([episode_id], [], None),
  )
  let old_ids = [
    @factepoch.FactId::new("payload-old-b"),
    @factepoch.FactId::new("payload-old-a"),
  ]
  let decision = @factepoch.ConflictDecision::new(
    "maintainer",
    "replace",
    candidate.id(),
    old_ids,
    SupersedeExisting,
  )
  let envelope = @factepoch.RecordedEvent::new(
    "payload-stream",
    1L,
    @factepoch.EventId::new("payload-event"),
    closure_time(300L),
    SupersedeFact(candidate, old_ids, decision),
  )
  old_ids.clear()
  match envelope.event() {
    SupersedeFact(_, ids, stored_decision) => {
      inspect(ids.length(), content="2")
      inspect(ids[0].value(), content="payload-old-a")
      inspect(stored_decision.prior_fact_ids().length(), content="2")
      ids.clear()
    }
    _ => fail("expected supersession event")
  }
  match envelope.event() {
    SupersedeFact(_, ids, _) => inspect(ids.length(), content="2")
    _ => fail("expected supersession event")
  }
}

///|
fn closure_event(
  seq : Int64,
  id : String,
  recorded_at : Int64,
  event : @factepoch.MemoryEvent,
) -> @factepoch.RecordedEvent raise @factepoch.MemoryError {
  @factepoch.RecordedEvent::new(
    "closure-stream",
    seq,
    @factepoch.EventId::new(id),
    closure_time(recorded_at),
    event,
  )
}

///|
fn closure_apply(
  graph : @factepoch.MemoryGraph,
  events : Array[@factepoch.RecordedEvent],
) -> @factepoch.ApplyReport {
  match graph.apply(events) {
    Ok(report) => report
    Err(_) => abort("closure fixture must apply")
  }
}

///|
fn closure_query(
  graph : @factepoch.MemoryGraph,
  valid_at : Int64,
  known_at : Int64,
  filter : @factepoch.FactFilter,
) -> Array[@factepoch.FactView] raise {
  match
    graph.query(
      @factepoch.FactQuery::new(
        closure_time(valid_at),
        closure_time(known_at),
        filter,
      ),
    ) {
    Ok(facts) => facts
    Err(_) => abort("valid closure query must succeed")
  }
}

///|
fn closure_decision(
  candidate : @factepoch.FactAssertion,
  old_ids : Array[@factepoch.FactId],
) -> @factepoch.ConflictDecision raise @factepoch.MemoryError {
  @factepoch.ConflictDecision::new(
    "maintainer",
    "reviewed replacement",
    candidate.id(),
    old_ids,
    SupersedeExisting,
  )
}

///|
fn inspect_guard(
  result : Result[@factepoch.ApplyReport, @factepoch.MemoryError],
  expected : @factepoch.SupersessionGuard,
) -> Unit raise {
  match result {
    Err(SupersessionGuardFailed(actual)) =>
      inspect(actual == expected, content="true")
    _ => fail("expected supersession structural guard")
  }
}

///|
test "literal supersession closes old valid time without mutating its assertion" {
  let group = @factepoch.GroupId::new("literal-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("literal-episode"),
    group,
    "The preference changed from MoonBit to Rust.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("literal-subject"),
    group,
    "Rin",
    "person",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let old_fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("literal-old"),
    group,
    subject.id(),
    "Prefers Language",
    Literal("MoonBit"),
    "Rin preferred MoonBit",
    closure_time(100L),
    None,
    8_500,
    provenance,
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("literal-new"),
    group,
    subject.id(),
    "prefers\tlanguage",
    Literal("Rust"),
    "Rin prefers Rust",
    closure_time(200L),
    None,
    9_500,
    provenance,
  )
  let decision = @factepoch.ConflictDecision::new(
    "maintainer",
    "new direct statement",
    candidate.id(),
    [old_fact.id()],
    SupersedeExisting,
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "literal-episode-event", 300L, RecordEpisode(episode)),
      closure_event(2L, "literal-subject-event", 300L, PutEntity(subject)),
      closure_event(3L, "literal-old-event", 300L, AssertFact(old_fact)),
    ]),
  )
  let supersede = closure_event(
    4L,
    "literal-supersede",
    500L,
    SupersedeFact(candidate, [old_fact.id()], decision),
  )
  let report = closure_apply(graph, [supersede])
  inspect(report.created_fact_count(), content="1")
  inspect(report.closed_fact_count(), content="1")
  let before_knowledge = closure_query(
    graph,
    250L,
    499L,
    @factepoch.FactFilter::new(predicate="prefers language"),
  )
  inspect(before_knowledge.length(), content="1")
  inspect(before_knowledge[0].fact().id().value(), content="literal-old")
  let before_cutoff = closure_query(
    graph,
    199L,
    500L,
    @factepoch.FactFilter::new(predicate="prefers language"),
  )
  inspect(before_cutoff.length(), content="1")
  inspect(before_cutoff[0].fact().id().value(), content="literal-old")
  let at_cutoff = closure_query(
    graph,
    200L,
    500L,
    @factepoch.FactFilter::new(predicate="prefers language"),
  )
  inspect(at_cutoff.length(), content="1")
  inspect(at_cutoff[0].fact().id().value(), content="literal-new")
  let history = match
    graph.history(
      @factepoch.HistoryQuery::new(
        ByFactId(old_fact.id()),
        closure_time(500L),
        closure_time(500L),
      ),
    ) {
    Ok(values) => values
    Err(_) => abort("history must succeed")
  }
  inspect(history.length(), content="1")
  inspect(history[0].fact().valid_to() == None, content="true")
  inspect(
    history[0].effective_valid_to().map(value => value.to_unix_millis()) ==
    Some(200L),
    content="true",
  )
  match history[0].closure() {
    Some(closure) => {
      inspect(closure.event_id().value(), content="literal-supersede")
      inspect(closure.recorded_at().to_unix_millis(), content="500")
      inspect(closure.effective_at().to_unix_millis(), content="200")
      match closure.cause() {
        SupersededBy(id, stored_decision) => {
          inspect(id.value(), content="literal-new")
          inspect(stored_decision.actor(), content="maintainer")
        }
        _ => fail("expected supersession cause")
      }
    }
    None => fail("old fact must retain an auditable closure")
  }
  let duplicate = closure_apply(graph, [supersede])
  inspect(duplicate.idempotent_event_ids().length(), content="1")
  inspect(duplicate.closed_fact_count(), content="0")
  let replayed = match @factepoch.MemoryGraph::replay(graph.snapshot_events()) {
    Ok(value) => value
    Err(_) => abort("closure stream must replay")
  }
  inspect(
    closure_query(replayed, 200L, 500L, @factepoch.FactFilter::all()) ==
    closure_query(graph, 200L, 500L, @factepoch.FactFilter::all()),
    content="true",
  )
  let replay_history_query = @factepoch.HistoryQuery::new(
    ByFactId(old_fact.id()),
    closure_time(300L),
    closure_time(500L),
  )
  inspect(
    graph.history(replay_history_query) ==
    replayed.history(replay_history_query),
    content="true",
  )
  let replay_diff_query = @factepoch.DiffQuery::new(
    AcrossKnowledge(closure_time(250L), closure_time(499L), closure_time(500L)),
    @factepoch.FactFilter::all(),
  )
  let original_diff = match graph.diff(replay_diff_query) {
    Ok(value) => value
    Err(_) => abort("original diff must succeed")
  }
  let replay_diff = match replayed.diff(replay_diff_query) {
    Ok(value) => value
    Err(_) => abort("replayed diff must succeed")
  }
  inspect(original_diff.added() == replay_diff.added(), content="true")
  inspect(original_diff.removed() == replay_diff.removed(), content="true")
  inspect(original_diff.unchanged() == replay_diff.unchanged(), content="true")
  let original_explain = match
    graph.explain(old_fact.id(), closure_time(250L), closure_time(500L)) {
    Ok(value) => value
    Err(_) => abort("original explanation must succeed")
  }
  let replay_explain = match
    replayed.explain(old_fact.id(), closure_time(250L), closure_time(500L)) {
    Ok(value) => value
    Err(_) => abort("replayed explanation must succeed")
  }
  inspect(original_explain.view() == replay_explain.view(), content="true")
  inspect(
    original_explain.visibility() == replay_explain.visibility(),
    content="true",
  )
  inspect(
    original_explain.source_episodes() == replay_explain.source_episodes(),
    content="true",
  )
  inspect(
    original_explain.lifecycle_events() == replay_explain.lifecycle_events(),
    content="true",
  )
}

///|
test "retraction is bitemporal and explain excludes future lifecycle events" {
  let group = @factepoch.GroupId::new("retract-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("retract-episode"),
    group,
    "The ticket was closed in error.",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("retract-subject"),
    group,
    "Ticket 42",
    "ticket",
    None,
    @factepoch.Metadata::empty(),
  )
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("retracted-fact"),
    group,
    subject.id(),
    "status",
    Literal("open"),
    "Ticket 42 was open",
    closure_time(100L),
    Some(closure_time(400L)),
    9_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "retract-episode-event", 300L, RecordEpisode(episode)),
      closure_event(2L, "retract-subject-event", 300L, PutEntity(subject)),
      closure_event(3L, "retract-assert", 300L, AssertFact(fact)),
      closure_event(
        4L,
        "retract-close",
        500L,
        RetractFact(fact.id(), closure_time(200L), "incorrect source"),
      ),
    ]),
  )
  inspect(
    closure_query(graph, 250L, 499L, @factepoch.FactFilter::all()).length(),
    content="1",
  )
  inspect(
    closure_query(graph, 199L, 500L, @factepoch.FactFilter::all()).length(),
    content="1",
  )
  inspect(
    closure_query(graph, 200L, 500L, @factepoch.FactFilter::all()).length(),
    content="0",
  )
  let before = match
    graph.explain(fact.id(), closure_time(250L), closure_time(499L)) {
    Ok(report) => report
    Err(_) => abort("fact is known before its future closure")
  }
  inspect(before.visibility() == Visible, content="true")
  inspect(before.lifecycle_events().length(), content="1")
  let after = match
    graph.explain(fact.id(), closure_time(250L), closure_time(500L)) {
    Ok(report) => report
    Err(_) => abort("closed fact remains explainable")
  }
  inspect(after.visibility() == EndedByRetraction, content="true")
  inspect(after.source_episodes().length(), content="1")
  inspect(after.activation_event().event_id().value(), content="retract-assert")
  let lifecycle = after.lifecycle_events()
  inspect(lifecycle.length(), content="2")
  inspect(lifecycle[0].event_id().value(), content="retract-assert")
  inspect(lifecycle[1].event_id().value(), content="retract-close")
  lifecycle.clear()
  inspect(after.lifecycle_events().length(), content="2")
  let sources = after.source_episodes()
  sources.clear()
  inspect(after.source_episodes().length(), content="1")
  let history = match
    graph.history(
      @factepoch.HistoryQuery::new(
        ByFactId(fact.id()),
        closure_time(500L),
        closure_time(500L),
      ),
    ) {
    Ok(values) => values
    Err(_) => abort("closed endpoint history must succeed")
  }
  inspect(history.length(), content="1")
  let knowledge_diff = match
    graph.diff(
      @factepoch.DiffQuery::new(
        AcrossKnowledge(
          closure_time(250L),
          closure_time(499L),
          closure_time(500L),
        ),
        @factepoch.FactFilter::all(),
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("knowledge diff must succeed")
  }
  inspect(knowledge_diff.removed().length(), content="1")
  inspect(knowledge_diff.removed()[0].closure() == None, content="true")
  inspect(knowledge_diff.added().length(), content="0")
  let validity_diff = match
    graph.diff(
      @factepoch.DiffQuery::new(
        AcrossValidity(
          closure_time(500L),
          closure_time(199L),
          closure_time(200L),
        ),
        @factepoch.FactFilter::all(),
      ),
    ) {
    Ok(value) => value
    Err(_) => abort("validity diff must succeed")
  }
  inspect(validity_diff.removed().length(), content="1")
  match graph.explain(fact.id(), closure_time(250L), closure_time(299L)) {
    Err(MissingFact(id)) => inspect(id == fact.id(), content="true")
    Err(_) => fail("unexpected error category")
    Ok(_) => fail("facts activated in the future must be missing")
  }
}

///|
test "a retraction keeps assertion endings and empty derived intervals auditable" {
  let group = @factepoch.GroupId::new("cutoff-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("cutoff-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("cutoff-subject"),
    group,
    "Subject",
    "thing",
    None,
    @factepoch.Metadata::empty(),
  )
  let before_start = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("cutoff-before"),
    group,
    subject.id(),
    "state",
    Literal("a"),
    "a",
    closure_time(100L),
    Some(closure_time(200L)),
    8_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let after_end = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("cutoff-after"),
    group,
    subject.id(),
    "phase",
    Literal("b"),
    "b",
    closure_time(100L),
    Some(closure_time(200L)),
    8_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "cutoff-episode-event", 300L, RecordEpisode(episode)),
      closure_event(2L, "cutoff-subject-event", 300L, PutEntity(subject)),
      closure_event(3L, "cutoff-before-assert", 300L, AssertFact(before_start)),
      closure_event(
        4L,
        "cutoff-before-close",
        300L,
        RetractFact(before_start.id(), closure_time(100L), "void"),
      ),
      closure_event(5L, "cutoff-after-assert", 300L, AssertFact(after_end)),
      closure_event(
        6L,
        "cutoff-after-close",
        300L,
        RetractFact(after_end.id(), closure_time(250L), "late"),
      ),
    ]),
  )
  inspect(
    closure_query(
      graph,
      100L,
      300L,
      @factepoch.FactFilter::new(predicate="state"),
    ).length(),
    content="0",
  )
  let ended = match
    graph.explain(after_end.id(), closure_time(200L), closure_time(300L)) {
    Ok(report) => report
    Err(_) => abort("known fact must be explainable")
  }
  inspect(
    ended.view().effective_valid_to().map(v => v.to_unix_millis()) == Some(200L),
    content="true",
  )
  inspect(ended.visibility() == EndedByAssertion, content="true")
}

///|
test "supersession guards every structural dimension before committing" {
  let group = @factepoch.GroupId::new("guard-group")
  let other_group = @factepoch.GroupId::new("guard-other-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("guard-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let other_episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("guard-other-episode"),
    other_group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("guard-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let other_subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("guard-other-subject"),
    group,
    "Other",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let foreign_subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("guard-foreign-subject"),
    other_group,
    "Foreign",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let endpoint = @factepoch.Entity::new(
    @factepoch.EntityId::new("guard-endpoint"),
    group,
    "Endpoint",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let other_endpoint = @factepoch.Entity::new(
    @factepoch.EntityId::new("guard-other-endpoint"),
    group,
    "Other endpoint",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let old = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-old"),
    group,
    subject.id(),
    "owns",
    EntityRef(endpoint.id()),
    "old edge",
    closure_time(100L),
    Some(closure_time(300L)),
    8_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "guard-episode-event", 300L, RecordEpisode(episode)),
      closure_event(
        2L,
        "guard-other-episode-event",
        300L,
        RecordEpisode(other_episode),
      ),
      closure_event(3L, "guard-subject-event", 300L, PutEntity(subject)),
      closure_event(
        4L,
        "guard-other-subject-event",
        300L,
        PutEntity(other_subject),
      ),
      closure_event(
        5L,
        "guard-foreign-subject-event",
        300L,
        PutEntity(foreign_subject),
      ),
      closure_event(6L, "guard-endpoint-event", 300L, PutEntity(endpoint)),
      closure_event(
        7L,
        "guard-other-endpoint-event",
        300L,
        PutEntity(other_endpoint),
      ),
      closure_event(8L, "guard-old-event", 300L, AssertFact(old)),
    ]),
  )
  let group_bad = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-group-bad"),
    other_group,
    foreign_subject.id(),
    "owns",
    Literal("x"),
    "bad",
    closure_time(200L),
    None,
    8_000,
    @factepoch.Provenance::new([other_episode.id()], [], None),
  )
  inspect_guard(
    graph.apply([
      closure_event(
        9L,
        "guard-group-fail",
        400L,
        SupersedeFact(
          group_bad,
          [old.id()],
          closure_decision(group_bad, [old.id()]),
        ),
      ),
    ]),
    GroupGuard,
  )
  let subject_bad = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-subject-bad"),
    group,
    other_subject.id(),
    "owns",
    EntityRef(endpoint.id()),
    "bad",
    closure_time(200L),
    None,
    8_000,
    provenance,
  )
  inspect_guard(
    graph.apply([
      closure_event(
        9L,
        "guard-subject-fail",
        400L,
        SupersedeFact(
          subject_bad,
          [old.id()],
          closure_decision(subject_bad, [old.id()]),
        ),
      ),
    ]),
    SubjectGuard,
  )
  let predicate_bad = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-predicate-bad"),
    group,
    subject.id(),
    "borrows",
    EntityRef(endpoint.id()),
    "bad",
    closure_time(200L),
    None,
    8_000,
    provenance,
  )
  inspect_guard(
    graph.apply([
      closure_event(
        9L,
        "guard-predicate-fail",
        400L,
        SupersedeFact(
          predicate_bad,
          [old.id()],
          closure_decision(predicate_bad, [old.id()]),
        ),
      ),
    ]),
    PredicateGuard,
  )
  let kind_bad = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-kind-bad"),
    group,
    subject.id(),
    "owns",
    Literal("endpoint"),
    "bad",
    closure_time(200L),
    None,
    8_000,
    provenance,
  )
  inspect_guard(
    graph.apply([
      closure_event(
        9L,
        "guard-kind-fail",
        400L,
        SupersedeFact(
          kind_bad,
          [old.id()],
          closure_decision(kind_bad, [old.id()]),
        ),
      ),
    ]),
    ObjectKindGuard,
  )
  let endpoint_bad = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-endpoint-bad"),
    group,
    subject.id(),
    "owns",
    EntityRef(other_endpoint.id()),
    "bad",
    closure_time(200L),
    None,
    8_000,
    provenance,
  )
  inspect_guard(
    graph.apply([
      closure_event(
        9L,
        "guard-endpoint-fail",
        400L,
        SupersedeFact(
          endpoint_bad,
          [old.id()],
          closure_decision(endpoint_bad, [old.id()]),
        ),
      ),
    ]),
    DirectedEndpointGuard,
  )
  let interval_bad = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-interval-bad"),
    group,
    subject.id(),
    "owns",
    EntityRef(endpoint.id()),
    "bad",
    closure_time(300L),
    None,
    8_000,
    provenance,
  )
  inspect_guard(
    graph.apply([
      closure_event(
        9L,
        "guard-interval-fail",
        400L,
        SupersedeFact(
          interval_bad,
          [old.id()],
          closure_decision(interval_bad, [old.id()]),
        ),
      ),
    ]),
    IntervalOverlapGuard,
  )
  let accepted = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("guard-accepted"),
    group,
    subject.id(),
    "OWNS",
    EntityRef(endpoint.id()),
    "new edge",
    closure_time(200L),
    None,
    9_000,
    provenance,
  )
  let report = closure_apply(graph, [
    closure_event(
      9L,
      "guard-success",
      400L,
      SupersedeFact(
        accepted,
        [old.id()],
        closure_decision(accepted, [old.id()]),
      ),
    ),
  ])
  inspect(report.closed_fact_count(), content="1")
  inspect(
    closure_query(graph, 200L, 400L, @factepoch.FactFilter::all())[0]
    .fact()
    .id() ==
    accepted.id(),
    content="true",
  )
}

///|
test "batch ordering reuses candidates and terminal closures reject a second close" {
  let group = @factepoch.GroupId::new("batch-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("batch-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("batch-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let old = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("batch-old"),
    group,
    subject.id(),
    "state",
    Literal("old"),
    "old",
    closure_time(100L),
    None,
    7_000,
    provenance,
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("batch-candidate"),
    group,
    subject.id(),
    "state",
    Literal("new"),
    "new",
    closure_time(200L),
    None,
    9_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  let report = closure_apply(graph, [
    closure_event(1L, "batch-episode-event", 300L, RecordEpisode(episode)),
    closure_event(2L, "batch-subject-event", 300L, PutEntity(subject)),
    closure_event(3L, "batch-old-event", 300L, AssertFact(old)),
    closure_event(4L, "batch-candidate-event", 400L, AssertFact(candidate)),
    closure_event(
      5L,
      "batch-supersede-event",
      400L,
      SupersedeFact(
        candidate,
        [old.id()],
        closure_decision(candidate, [old.id()]),
      ),
    ),
    closure_event(6L, "batch-candidate-noop", 400L, AssertFact(candidate)),
  ])
  inspect(report.created_fact_count(), content="2")
  inspect(report.closed_fact_count(), content="1")
  let explanation = match
    graph.explain(candidate.id(), closure_time(200L), closure_time(400L)) {
    Ok(value) => value
    Err(_) => abort("candidate must be explainable")
  }
  inspect(
    explanation.activation_event().event_id().value(),
    content="batch-candidate-event",
  )
  inspect(explanation.lifecycle_events().length(), content="2")
  let length_before = graph.snapshot_events().length()
  match
    graph.apply([
      closure_event(
        7L,
        "batch-second-close",
        500L,
        RetractFact(old.id(), closure_time(250L), "second"),
      ),
    ]) {
    Err(FactAlreadyClosed(id)) => inspect(id == old.id(), content="true")
    _ => fail("a second terminal closure must fail")
  }
  inspect(graph.snapshot_events().length() == length_before, content="true")
  match
    graph.apply([
      closure_event(
        7L,
        "batch-missing-close",
        500L,
        RetractFact(
          @factepoch.FactId::new("missing"),
          closure_time(250L),
          "missing",
        ),
      ),
    ]) {
    Err(MissingFact(id)) => inspect(id.value(), content="missing")
    _ => fail("a missing close target must fail")
  }
  let rejected = @factepoch.ConflictDecision::new(
    "maintainer",
    "reject",
    @factepoch.FactId::new("rejected-candidate"),
    [candidate.id()],
    RejectCandidate,
  )
  let rejected_candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("rejected-candidate"),
    group,
    subject.id(),
    "state",
    Literal("later"),
    "later",
    closure_time(300L),
    None,
    9_000,
    provenance,
  )
  match
    graph.apply([
      closure_event(
        7L,
        "batch-action-mismatch",
        500L,
        SupersedeFact(rejected_candidate, [candidate.id()], rejected),
      ),
    ]) {
    Err(ConflictDecisionMismatch(field)) => inspect(field, content="action")
    _ => fail("decision action must authorize supersession")
  }
  let wrong_candidate_decision = @factepoch.ConflictDecision::new(
    "maintainer",
    "wrong candidate",
    @factepoch.FactId::new("different-candidate"),
    [candidate.id()],
    SupersedeExisting,
  )
  match
    graph.apply([
      closure_event(
        7L,
        "batch-candidate-mismatch",
        500L,
        SupersedeFact(
          rejected_candidate,
          [candidate.id()],
          wrong_candidate_decision,
        ),
      ),
    ]) {
    Err(ConflictDecisionMismatch(field)) =>
      inspect(field, content="candidate_fact_id")
    _ => fail("decision candidate must match event candidate")
  }
  let wrong_prior_decision = @factepoch.ConflictDecision::new(
    "maintainer",
    "wrong prior",
    rejected_candidate.id(),
    [old.id()],
    SupersedeExisting,
  )
  match
    graph.apply([
      closure_event(
        7L,
        "batch-prior-mismatch",
        500L,
        SupersedeFact(
          rejected_candidate,
          [candidate.id()],
          wrong_prior_decision,
        ),
      ),
    ]) {
    Err(ConflictDecisionMismatch(field)) =>
      inspect(field, content="prior_fact_ids")
    _ => fail("decision prior set must match event prior set")
  }
}

///|
test "same-millisecond assertion and retraction are both known" {
  let group = @factepoch.GroupId::new("same-ms-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("same-ms-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("same-ms-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let fact = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("same-ms-fact"),
    group,
    subject.id(),
    "state",
    Literal("brief"),
    "brief",
    closure_time(100L),
    None,
    8_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "same-ms-episode-event", 500L, RecordEpisode(episode)),
      closure_event(2L, "same-ms-subject-event", 500L, PutEntity(subject)),
      closure_event(3L, "same-ms-assert", 500L, AssertFact(fact)),
      closure_event(
        4L,
        "same-ms-retract",
        500L,
        RetractFact(fact.id(), closure_time(100L), "immediate correction"),
      ),
    ]),
  )
  inspect(
    closure_query(graph, 100L, 500L, @factepoch.FactFilter::all()).length(),
    content="0",
  )
  let history = match
    graph.history(
      @factepoch.HistoryQuery::new(
        ByFactId(fact.id()),
        closure_time(500L),
        closure_time(500L),
      ),
    ) {
    Ok(values) => values
    Err(_) => abort("same millisecond history must succeed")
  }
  inspect(history.length(), content="1")
  inspect(history[0].closure() is Some(_), content="true")
}

///|
test "multi-fact supersession validates every prior before closing any" {
  let group = @factepoch.GroupId::new("atomic-close-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("atomic-close-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let first_subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("atomic-first-subject"),
    group,
    "First",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let second_subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("atomic-second-subject"),
    group,
    "Second",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let first = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("atomic-first"),
    group,
    first_subject.id(),
    "state",
    Literal("old"),
    "old",
    closure_time(100L),
    None,
    8_000,
    provenance,
  )
  let second = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("atomic-second"),
    group,
    second_subject.id(),
    "state",
    Literal("old"),
    "old",
    closure_time(100L),
    None,
    8_000,
    provenance,
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("atomic-candidate"),
    group,
    first_subject.id(),
    "state",
    Literal("new"),
    "new",
    closure_time(200L),
    None,
    9_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "atomic-episode-event", 300L, RecordEpisode(episode)),
      closure_event(
        2L,
        "atomic-first-subject-event",
        300L,
        PutEntity(first_subject),
      ),
      closure_event(
        3L,
        "atomic-second-subject-event",
        300L,
        PutEntity(second_subject),
      ),
      closure_event(4L, "atomic-first-event", 300L, AssertFact(first)),
      closure_event(5L, "atomic-second-event", 300L, AssertFact(second)),
    ]),
  )
  let prior = [first.id(), second.id()]
  inspect_guard(
    graph.apply([
      closure_event(
        6L,
        "atomic-rejected",
        400L,
        SupersedeFact(candidate, prior, closure_decision(candidate, prior)),
      ),
    ]),
    SubjectGuard,
  )
  inspect(graph.snapshot_events().length(), content="5")
  inspect(
    closure_query(graph, 250L, 400L, @factepoch.FactFilter::all()).length(),
    content="2",
  )
  let first_report = match
    graph.explain(first.id(), closure_time(250L), closure_time(400L)) {
    Ok(value) => value
    Err(_) => abort("first old fact must remain")
  }
  inspect(first_report.view().closure() == None, content="true")
  match graph.explain(candidate.id(), closure_time(250L), closure_time(400L)) {
    Err(MissingFact(_)) => ()
    _ => fail("candidate from rejected batch must not publish")
  }
}

///|
test "multi-fact closure and future-valid candidates preserve lifecycle facts" {
  let group = @factepoch.GroupId::new("multi-success-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("multi-success-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("multi-success-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let first = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("multi-success-first"),
    group,
    subject.id(),
    "state",
    Literal("one"),
    "one",
    closure_time(100L),
    None,
    7_000,
    provenance,
  )
  let second = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("multi-success-second"),
    group,
    subject.id(),
    "STATE",
    Literal("two"),
    "two",
    closure_time(200L),
    None,
    8_000,
    provenance,
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("multi-success-candidate"),
    group,
    subject.id(),
    "state",
    Literal("future"),
    "future",
    closure_time(1_000L),
    None,
    9_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(
        1L,
        "multi-success-episode-event",
        300L,
        RecordEpisode(episode),
      ),
      closure_event(2L, "multi-success-subject-event", 300L, PutEntity(subject)),
      closure_event(3L, "multi-success-first-event", 300L, AssertFact(first)),
      closure_event(4L, "multi-success-second-event", 300L, AssertFact(second)),
    ]),
  )
  let ids = [second.id(), first.id()]
  let supersede = closure_event(
    5L,
    "multi-success-event",
    500L,
    SupersedeFact(candidate, ids, closure_decision(candidate, ids)),
  )
  let report = closure_apply(graph, [supersede])
  inspect(report.closed_fact_count(), content="2")
  inspect(report.created_fact_count(), content="1")
  inspect(
    closure_query(graph, 600L, 500L, @factepoch.FactFilter::all()).length(),
    content="2",
  )
  inspect(
    closure_query(graph, 1_000L, 500L, @factepoch.FactFilter::all()).length(),
    content="1",
  )
  let later_assert = closure_apply(graph, [
    closure_event(6L, "multi-success-later-assert", 500L, AssertFact(candidate)),
  ])
  inspect(later_assert.created_fact_count(), content="0")
  let explanation = match
    graph.explain(candidate.id(), closure_time(1_000L), closure_time(500L)) {
    Ok(value) => value
    Err(_) => abort("candidate must be explainable")
  }
  inspect(
    explanation.activation_event().event_id().value(),
    content="multi-success-event",
  )
  inspect(explanation.lifecycle_events().length(), content="1")
  for id in [first.id(), second.id()] {
    let old = match
      graph.explain(id, closure_time(1_000L), closure_time(500L)) {
      Ok(value) => value
      Err(_) => abort("closed prior must be explainable")
    }
    inspect(
      old.visibility() == EndedBySupersession(candidate.id()),
      content="true",
    )
  }
}

///|
test "supersession may derive an empty old interval at or before its start" {
  let group = @factepoch.GroupId::new("empty-supersede-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("empty-supersede-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("empty-supersede-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let old = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("empty-supersede-old"),
    group,
    subject.id(),
    "state",
    Literal("old"),
    "old",
    closure_time(100L),
    Some(closure_time(300L)),
    8_000,
    provenance,
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("empty-supersede-candidate"),
    group,
    subject.id(),
    "state",
    Literal("corrected"),
    "corrected",
    closure_time(50L),
    Some(closure_time(200L)),
    9_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(
        1L,
        "empty-supersede-episode-event",
        300L,
        RecordEpisode(episode),
      ),
      closure_event(
        2L,
        "empty-supersede-subject-event",
        300L,
        PutEntity(subject),
      ),
      closure_event(3L, "empty-supersede-old-event", 300L, AssertFact(old)),
      closure_event(
        4L,
        "empty-supersede-event",
        400L,
        SupersedeFact(
          candidate,
          [old.id()],
          closure_decision(candidate, [old.id()]),
        ),
      ),
    ]),
  )
  let explanation = match
    graph.explain(old.id(), closure_time(100L), closure_time(400L)) {
    Ok(value) => value
    Err(_) => abort("old fact must be explainable")
  }
  inspect(
    explanation.view().effective_valid_to().map(v => v.to_unix_millis()) ==
    Some(50L),
    content="true",
  )
  inspect(
    explanation.visibility() == EndedBySupersession(candidate.id()),
    content="true",
  )
  inspect(
    closure_query(graph, 100L, 400L, @factepoch.FactFilter::all()).length(),
    content="1",
  )
}

///|
test "event identity wins over changed supersession payloads" {
  let group = @factepoch.GroupId::new("event-conflict-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("event-conflict-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("event-conflict-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let provenance = @factepoch.Provenance::new([episode.id()], [], None)
  let first = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("event-conflict-first"),
    group,
    subject.id(),
    "state",
    Literal("one"),
    "one",
    closure_time(100L),
    None,
    7_000,
    provenance,
  )
  let second = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("event-conflict-second"),
    group,
    subject.id(),
    "state",
    Literal("two"),
    "two",
    closure_time(100L),
    None,
    7_000,
    provenance,
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("event-conflict-candidate"),
    group,
    subject.id(),
    "state",
    Literal("new"),
    "new",
    closure_time(200L),
    None,
    9_000,
    provenance,
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(
        1L,
        "event-conflict-episode-event",
        300L,
        RecordEpisode(episode),
      ),
      closure_event(
        2L,
        "event-conflict-subject-event",
        300L,
        PutEntity(subject),
      ),
      closure_event(3L, "event-conflict-first-event", 300L, AssertFact(first)),
      closure_event(4L, "event-conflict-second-event", 300L, AssertFact(second)),
      closure_event(
        5L,
        "event-conflict-supersede",
        400L,
        SupersedeFact(
          candidate,
          [first.id()],
          closure_decision(candidate, [first.id()]),
        ),
      ),
    ]),
  )
  let changed_cutoff = @factepoch.FactAssertion::new(
    candidate.id(),
    group,
    subject.id(),
    "state",
    Literal("new"),
    "new",
    closure_time(250L),
    None,
    9_000,
    provenance,
  )
  let variants : Array[@factepoch.MemoryEvent] = [
    SupersedeFact(
      candidate,
      [second.id()],
      closure_decision(candidate, [second.id()]),
    ),
    SupersedeFact(
      candidate,
      [first.id()],
      @factepoch.ConflictDecision::new(
        "other",
        "different",
        candidate.id(),
        [first.id()],
        SupersedeExisting,
      ),
    ),
    SupersedeFact(
      changed_cutoff,
      [first.id()],
      closure_decision(changed_cutoff, [first.id()]),
    ),
  ]
  for variant in variants {
    match
      graph.apply([closure_event(5L, "event-conflict-supersede", 400L, variant)]) {
      Err(EventIdConflict(id)) =>
        inspect(id.value(), content="event-conflict-supersede")
      _ => fail("event ID conflict must precede payload validation")
    }
  }
}

///|
test "candidate reference validation precedes old-fact structural guards" {
  let group = @factepoch.GroupId::new("priority-group")
  let episode = @factepoch.Episode::new(
    @factepoch.EpisodeId::new("priority-episode"),
    group,
    "source",
    None,
    None,
    None,
    @factepoch.Metadata::empty(),
  )
  let subject = @factepoch.Entity::new(
    @factepoch.EntityId::new("priority-subject"),
    group,
    "Subject",
    "node",
    None,
    @factepoch.Metadata::empty(),
  )
  let old = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("priority-old"),
    group,
    subject.id(),
    "state",
    Literal("old"),
    "old",
    closure_time(100L),
    None,
    8_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let candidate = @factepoch.FactAssertion::new(
    @factepoch.FactId::new("priority-candidate"),
    group,
    @factepoch.EntityId::new("priority-missing-subject"),
    "different",
    Literal("new"),
    "new",
    closure_time(200L),
    None,
    9_000,
    @factepoch.Provenance::new([episode.id()], [], None),
  )
  let graph = @factepoch.MemoryGraph::new()
  ignore(
    closure_apply(graph, [
      closure_event(1L, "priority-episode-event", 300L, RecordEpisode(episode)),
      closure_event(2L, "priority-subject-event", 300L, PutEntity(subject)),
      closure_event(3L, "priority-old-event", 300L, AssertFact(old)),
    ]),
  )
  match
    graph.apply([
      closure_event(
        4L,
        "priority-supersede",
        400L,
        SupersedeFact(
          candidate,
          [old.id()],
          closure_decision(candidate, [old.id()]),
        ),
      ),
    ]) {
    Err(MissingEntity(id)) =>
      inspect(id.value(), content="priority-missing-subject")
    _ =>
      fail("candidate references must be validated before old-fact structure")
  }
}
