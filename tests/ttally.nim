## The README's example: it builds against its model file and behaves as the README says.
import std/unittest
import eversince
import ../examples/tally/tally

suite "tally example":
  test "a command is accepted, folded into the view and answered":
    var rt = Runtime[TallyApp](store: MemStore(), clock: proc (): int64 = 1000)
    check not rt.execute("Count", %*{"by": 3}).refused
    check not rt.execute("Count", %*{"by": 4}).refused
    check rt.app.answer("CurrentTotal", %*{}) == %7
    check rt.seq == 2

  test "refusals use the declared codes and store nothing":
    var rt = Runtime[TallyApp](store: MemStore(), clock: proc (): int64 = 1000)
    check rt.execute("Count", %*{"by": 0}).code == "notPositive"
    check rt.execute("Count", %*{"by": 101}).code == "tooMany"
    check rt.seq == 0
    check rt.store.load.len == 0

  test "an unknown command is refused as unknownCommand":
    var rt = Runtime[TallyApp](store: MemStore(), clock: proc (): int64 = 1000)
    check rt.execute("Nope", %*{}).code == "unknownCommand"
