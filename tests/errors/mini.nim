## The fixture of tests/terrors.nim: the smallest app with every kind of block. The test copies this
## file and mini.em to a scratch folder, makes one mistake in the copy and checks what the build says.
## The `#@name` marks are how the test finds a line; they are not part of the example.
import std/os
import eversince

event Counted:
  by: int
event Reset:
  to: int

view Tally:
  state:
    total: int
  on Counted: #@viewOn
    state.total += e.by
  on Reset:
    state.total = e.to

command Count: #@command
  fields:
    by: int
  reads Tally
  produces Counted #@produces
  refuses notPositive
  decide: #@decide
    if cmd.by <= 0: refuse notPositive, "Count at least one."
    emit Counted(by: cmd.by) #@emit

command Clear:
  reads Tally
  produces Reset
  decide:
    emit Reset(to: 0)

query CurrentTotal:
  reads Tally
  returns int
  answer: tally.total #@answer

processor Notifier:
  issues Clear #@issues
  on Counted:
    issue Clear() #@issue

sealModel(MiniApp, currentSourcePath().parentDir / "mini.em") #@seal
