## Error messages: a build that breaks a rule stops on the user's own line, names the block and says
## what to do. Each test makes one mistake in a copy of tests/errors/mini.nim (and mini.em), runs
## `nim check` on it and asserts the core of the message and where it was reported.
## The `#@name` marks in the fixture are how a test finds a line.
import std/[unittest, os, osproc, strutils, sequtils]
import eversince/model

const root = currentSourcePath().parentDir.parentDir

type Build = object
  ok: bool
  output, src, em: string
  errors: seq[string]       ## the lines of the output that carry an error

proc lineOf(text, marker: string): int =
  ## The 1-based line of the first line that contains `marker`.
  let lines = text.splitLines
  for i, l in lines:
    if marker in l: return i + 1
  raise newException(ValueError, "the text has no line with `" & marker & "`")

proc edited(text: string, edits: openArray[(string, string)]): string =
  result = text
  for (a, b) in edits:
    doAssert a in result, "the fixture has no `" & a & "`"
    result = result.replace(a, b)

proc build(name: string, src: openArray[(string, string)] = [], em: openArray[(string, string)] = [],
           flags = ""): Build =
  let dir = getTempDir() / "eversince-terrors" / name
  removeDir dir
  createDir dir
  result.src = readFile(root / "tests" / "errors" / "mini.nim").edited(src)
  result.em = readFile(root / "tests" / "errors" / "mini.em").edited(em)
  writeFile(dir / "mini.nim", result.src)
  writeFile(dir / "mini.em", result.em)
  let (output, code) = execCmdEx(quoteShell(getCurrentCompilerExe()) & " check --hints:off --warnings:off " &
    flags & " --path:" & quoteShell(root / "src") & " " & quoteShell(dir / "mini.nim"))
  result.ok = code == 0
  result.output = output
  result.errors = output.splitLines.filterIt(" Error: " in it)
  removeDir dir

proc firstError(b: Build): string = b.errors[0]

proc reportedAt(b: Build, marker: string): bool =
  ## The first error is reported at the line of `marker` in mini.nim.
  b.errors.len > 0 and ("mini.nim(" & $b.src.lineOf(marker) & ", ") in b.firstError

proc inUsersFile(b: Build): bool =
  ## Every error names mini.nim, never the kit's files or a generated text without a file.
  b.errors.allIt("mini.nim(" in it) and not b.output.contains("blocks.nim") and not b.output.contains("model.nim")

suite "the fixture":
  test "builds clean, so every failure below comes from its one mistake":
    let b = build("clean")
    check b.ok
    check b.errors.len == 0

suite "a rule of a declaration, reported on the user's line":
  test "emit of an event `produces` does not list: on the emit line, with the fix":
    let b = build("emit", src = {"    emit Counted(by: cmd.by) #@emit": "    emit Counted(by: cmd.by)\n    emit Reset(to: 0) #@bad"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "command Count emits Reset, which its `produces` line does not list" in b.firstError
    check "add Reset to `produces`" in b.firstError
    check b.inUsersFile

  test "issue of a command `issues` does not list: on the issue line, with the fix":
    let b = build("issue", src = {"    issue Clear() #@issue": "    issue Clear()\n    issue Count(by: 1) #@bad"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "processor Notifier issues Count, which its `issues` line does not list" in b.firstError
    check "add Count to `issues`" in b.firstError
    check b.inUsersFile

  test "a clock or a print in decide: reported on the decide line, the hint on the print":
    let b = build("clock", src = {"    emit Counted(by: cmd.by) #@emit": "    emit Counted(by: cmd.by)\n    echo \"now\" #@bad"})
    check not b.ok
    check b.reportedAt("#@decide")
    check "'decide' can have side effects" in b.firstError
    check ("mini.nim(" & $b.src.lineOf("#@bad") & ", ") in b.output   # the hint names the print
    check b.inUsersFile

  test "reading the environment in a view's fold: on the line that reads it":
    let b = build("env", src = {"    state.total += e.by": "    state.total += e.by + getEnv(\"HOME\").len #@bad"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "ReadEnvEffect" in b.firstError
    check b.inUsersFile

  test "a query that changes a view: on the line that changes it":
    let b = build("query", src = {"  answer: tally.total #@answer": "  answer:\n    tally.total = 0 #@bad\n    tally.total"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "'tally.total' cannot be assigned to" in b.firstError
    check b.inUsersFile

  test "a misspelt event in `produces`: on that name, not on the decide":
    let b = build("misspelt", src = {"  produces Counted #@produces": "  produces Countd #@bad"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "undeclared identifier: 'Countd'" in b.firstError
    check b.inUsersFile

  test "two blocks of one name: on the second, naming the first":
    let b = build("twice", src = {"command Clear:": "event Reset: #@bad\n  to: int\n\ncommand Clear:"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "`Reset` is declared twice" in b.firstError
    check ("first declared at mini.nim:" & $b.src.lineOf("event Reset:")) in b.firstError
    check b.inUsersFile

  test "a command without decide: on the command's name, with the fix":
    let b = build("nodecide", src = {"  decide:\n    emit Reset(to: 0)\n": ""})
    check not b.ok
    check b.reportedAt("command Clear:")
    check "command Clear has no decide: section" in b.firstError
    check "add `decide:`" in b.firstError
    check b.inUsersFile

  test "a section the block does not have: on that section, naming it":
    let b = build("section", src = {"  produces Reset": "  writes Tally #@bad\n  produces Reset"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "command Clear: expected fields:, reads, produces, refuses or decide:, found `writes`" in b.firstError
    check b.inUsersFile

  test "a view that handles one event twice: on the second handler, with the fix":
    let b = build("handlesTwice", src = {"  on Reset:": "  on Counted: #@bad\n    state.total = 0\n  on Reset:"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "view Tally handles Counted twice" in b.firstError
    check "merge the two `on Counted:` bodies" in b.firstError
    check b.inUsersFile

  test "a field that is not `name: Type`: on the field, naming the block":
    let b = build("field", src = {"  to: int": "  to #@bad"})
    check not b.ok
    check b.reportedAt("#@bad")
    check "event Reset: expected `name: Type` for a field, found `to`" in b.firstError
    check b.inUsersFile

suite "the model file against the code, reported on the sealModel line":
  test "a block that differs: both lines, and where each one is":
    let b = build("differs", em = {"command Clear | reads Tally | produces Reset":
                                   "command Clear | reads Tally | produces Reset,Counted"})
    check not b.ok
    check b.reportedAt("#@seal")
    check "event model mini.em does not match the code" in b.firstError
    check "model and code disagree about `command Clear`" in b.output
    check ("mini.em:" & $b.em.lineOf("command Clear")) in b.output
    check ("code: mini.nim:" & $b.src.lineOf("command Clear:")) in b.output
    check "model: command Clear | reads Tally | produces Counted,Reset" in b.output
    check "code:  command Clear | reads Tally | produces Reset" in b.output
    check b.inUsersFile

  test "a block the code lacks: the model's line, to write or delete":
    let b = build("lacks", em = {"event Reset to:int": "event Reset to:int\nevent Extra x:int"})
    check not b.ok
    check b.reportedAt("#@seal")
    check ("mini.em:" & $b.em.lineOf("event Extra") & ": the model declares a block the code lacks") in b.output
    check "event Extra x:int" in b.output
    check b.inUsersFile

  test "a block the model lacks: the code's line, and the line to add":
    let b = build("missing", em = {"event Reset to:int\n": "", "slice tidy up : Counted -> Notifier -> Clear -> Reset\n": ""})
    check not b.ok
    check b.reportedAt("#@seal")
    check ("mini.nim:" & $b.src.lineOf("event Reset:") & ": the code declares a block the model lacks") in b.output
    check "event Reset to:int" in b.output
    check b.inUsersFile

  test "a slice that names a block that does not exist: the slice's line":
    let b = build("ghost", em = {"slice count up": "slice ghost : Counter -> Nope\nslice count up"})
    check not b.ok
    check b.reportedAt("#@seal")
    check ("mini.em:" & $b.em.lineOf("slice ghost") & ": slice \"ghost\": `Nope` does not exist") in b.output
    check "declare the block" in b.output
    check b.inUsersFile

  test "a slice step the blocks do not declare: the fix that would make it true":
    let b = build("step", em = {"slice count up": "slice jump : Counter -> Clear\nslice count up"})
    check not b.ok
    check ("mini.em:" & $b.em.lineOf("slice jump") & ": slice \"jump\": Counter -> Clear is not an edge the blocks declare") in b.output
    check "add `Clear` to the `commands` of screen Counter" in b.output
    check b.inUsersFile

  test "a step from one kind to a kind nothing connects: the allowed steps":
    let b = build("kinds", em = {"slice count up": "slice leap : Counter -> Counted\nslice count up"})
    check not b.ok
    check "a screen cannot lead to an event (Counter -> Counted)" in b.output
    check "screen->command" in b.output
    check b.inUsersFile

  test "a line of the model that does not parse: its line, and what it needs":
    let b = build("parse", em = {"slice count up": "slice no colon here\nslice count up"})
    check not b.ok
    check b.reportedAt("#@seal")
    check "event model mini.em does not parse" in b.firstError
    check ("mini.em:" & $b.em.lineOf("slice no colon") & ": slice line needs `slice title : A -> B`") in b.output
    check b.inUsersFile

  test "a lint is a warning, and under -d:eversinceStrict an error with the line and the fix":
    let em = {"screen Counter | queries CurrentTotal | commands Count": "screen Counter | commands Count",
              "Counter -> Count -> Counted -> Tally -> CurrentTotal -> Counter": "Counter -> Count -> Counted -> Tally"}
    check build("lint", em = em).ok
    let b = build("strict", em = em, flags = "-d:eversinceStrict")
    check not b.ok
    check b.reportedAt("#@seal")
    check "event model (strict): lints are errors under -d:eversinceStrict" in b.firstError
    check ("mini.em:" & $b.em.lineOf("query CurrentTotal") & ": query CurrentTotal is on no screen") in b.output
    check "add it to a screen's `queries`" in b.output
    check b.inUsersFile

suite "the checker's own messages (no build)":
  let base = """
screen S | commands Go
command Go x:int | reads V | produces Done | refuses no
event Done x:int
view V n:int | consumes Done
query Q | reads V | returns int
screen S2 | queries Q
slice go : S -> Go -> Done -> V -> Q -> S2
"""
  proc codeOf(m: Model): seq[string] = m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical)

  test "a parse error is a ModelParseError that names the file and the line":
    for (text, line, core) in [("event A x:int\nslice oops\n", 2, "slice line needs"),
                               ("event A x:int\n\nevent\n", 3, "model line needs a kind and a name"),
                               ("event A x:int | reads\n", 1, "edge needs a key and values")]:
      let e = try: (discard parseModel(text, "desk.em"); "") except ModelParseError as e: e.msg
      check e.startsWith("desk.em:" & $line & ": ")
      check core in e
    let e = try: (discard parseModel("slice oops"); "") except ModelParseError as e: e.msg
    check e.startsWith("line 1: ")

  test "blocks and slices remember their line in the model":
    let m = parseModel(base)
    check m.blocks[0].line == 1
    check m.blocks[^1].line == 6
    check m.slices[0].line == 7

  test "each difference starts with the model line to look at":
    let m = parseModel(base)
    let r = checkModel(m, codeOf(m).filterIt(not it.startsWith("event Done")), "m.em")
    check r.errors.anyIt(it.startsWith("m.em:3: the model declares a block the code lacks"))

  test "a slice names a missing block once, not once per step":
    let m = parseModel(base.replace("Go -> Done -> V", "Go -> Gone -> V"))
    let r = checkModel(m, codeOf(m), "m.em")
    check r.errors.countIt("`Gone` does not exist" in it) == 1

  test "a lint carries the model line and the fix":
    let m = parseModel(base & "command Orphan | reads V | produces Done\n")
    let r = checkModel(m, codeOf(m), "m.em")
    check r.errors.len == 0
    check r.warnings.anyIt(it.startsWith("m.em:8: command Orphan is on no screen and issued by no processor (add it to"))
