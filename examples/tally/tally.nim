import std/os
import eversince

event Counted:
  by: int

view Tally:
  state:
    total: int
  on Counted:
    state.total += e.by

command Count:
  fields:
    by: int
  reads Tally
  produces Counted
  refuses notPositive, tooMany
  decide:
    if cmd.by <= 0: refuse notPositive, "Count at least one."
    if tally.total + cmd.by > 100: refuse tooMany, "The tally stops at 100."
    emit Counted(by: cmd.by)

query CurrentTotal:
  reads Tally
  returns int
  answer: tally.total

sealModel(TallyApp, currentSourcePath().parentDir / "tally.em")
