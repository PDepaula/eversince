## The model file: parsing, the canonical line, and every kind of difference the checker reports.
import std/[unittest, os, strutils, sequtils]
import eversince

let deskText = readFile(currentSourcePath().parentDir / ".." / "examples" / "desk" / "desk.em")

proc codeOf(m: Model): seq[string] =
  m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical)

suite "model file":
  test "the desk model parses to the documented size":
    let m = parseModel(deskText)
    check m.counts == "8 commands, 9 events, 2 views, 2 query/queries, 2 processors, 2 screens, 6 slices"

  test "comments and blank lines are free, order does not matter":
    let m = parseModel("# a comment\n\nevent B x:int # trailing\nevent A y:string\n")
    check m.blocks.mapIt(it.name) == @["B", "A"]
    check m.blocks[0].canonical == "event B x:int"

  test "canonical writes edges in a fixed order with sorted values":
    let m = parseModel("command C a:int | refuses z,a | produces E2,E1 | reads V")
    check m.blocks[0].canonical == "command C a:int | reads V | produces E1,E2 | refuses a,z"

  test "a slice line is a name and a path":
    let m = parseModel("slice a story : A -> B -> C")
    check m.slices.len == 1
    check m.slices[0].name == "a story"
    check m.slices[0].steps == @["A", "B", "C"]

suite "model check":
  let base = """
screen S | commands Go
command Go x:int | reads V | produces Done | refuses no
event Done x:int
view V n:int | consumes Done
query Q | reads V | returns int
screen S2 | queries Q
slice go : S -> Go -> Done -> V -> Q -> S2
"""

  test "a model that matches its code has no errors":
    let m = parseModel(base)
    let r = checkModel(m, codeOf(m))
    check r.errors.len == 0

  test "a block the code lacks is reported with its line":
    let m = parseModel(base)
    let r = checkModel(m, codeOf(m).filterIt(not it.startsWith("event Done")))
    check r.errors.anyIt("the model declares a block the code lacks" in it and "event Done x:int" in it)

  test "a block the model lacks is reported with the line to add":
    let m = parseModel(base)
    let r = checkModel(m, codeOf(m) & "event Extra y:int")
    check r.errors.anyIt("the code declares a block the model lacks" in it and "event Extra y:int" in it)

  test "a block that differs shows both lines":
    let m = parseModel(base)
    let changed = codeOf(m).mapIt(if it.startsWith("command Go"): "command Go x:int | reads V | produces Done | refuses no,other" else: it)
    let r = checkModel(m, changed)
    check r.errors.anyIt("model and code disagree about `command Go`" in it and "model:" in it and "code:" in it)

  test "a slice step that is not an edge is reported":
    let m = parseModel(base.replace("S -> Go -> Done", "S -> Done"))
    let r = checkModel(m, codeOf(m))
    check r.errors.anyIt("S -> Done" in it)

  test "a slice that names nothing real is reported":
    let m = parseModel(base & "slice ghost : S -> Nothing\n")
    let r = checkModel(m, codeOf(m))
    check r.errors.anyIt("`Nothing` does not exist" in it)

  test "a screen that names a missing block is reported":
    let m = parseModel(base & "screen Bad | commands Missing\n")
    let r = checkModel(m, codeOf(m))
    check r.errors.anyIt("screen Bad names `Missing`" in it)

  test "lints: a command on no screen and issued by no processor":
    let m = parseModel(base & "command Orphan | reads V | produces Done\n")
    let r = checkModel(m, codeOf(m))
    check r.errors.len == 0
    check r.warnings.anyIt("command Orphan is on no screen and issued by no processor" in it)
