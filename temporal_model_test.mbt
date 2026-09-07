// SPDX-License-Identifier: Apache-2.0

///|
test "valid intervals are half-open" {
  let start = @factepoch.Timestamp::from_unix_millis(100L)
  let stop = @factepoch.Timestamp::from_unix_millis(200L)
  let interval = @factepoch.ValidInterval::new(start, Some(stop))
  inspect(interval.contains(start), content="true")
  inspect(interval.contains(stop), content="false")
  try @factepoch.ValidInterval::new(start, Some(start)) catch {
    InvalidInterval(_, _) => ()
    _ => fail("expected InvalidInterval")
  } noraise {
    _ => fail("empty interval must fail")
  }
}

///|
test "domain constructors reject blank values" {
  try @factepoch.EventId::new("   ") catch {
    InvalidId(_) => ()
    _ => fail("expected InvalidId")
  } noraise {
    _ => fail("blank id must fail")
  }
  let group = @factepoch.GroupId::new("profile")
  try
    @factepoch.Entity::new(@factepoch.EntityId::new("mira"), group, "")
  catch {
    InvalidField("entity.name") => ()
    _ => fail("expected entity.name error")
  } noraise {
    _ => fail("blank entity name must fail")
  }
}
