## The command line as a library: the catalogue, the picture, the check report, the scenario
## runner, and the exit code of every way a command can end. No process is started here
## (`tcli_e2e` does that); `dispatch` is called and what it wrote is read back.
##
## The golden files in tests/golden/ are the exact bytes `catalog` and `pic` print for the desk
## model. A change to either shows up as a diff of a reviewable file. To accept a change:
##   EVERSINCE_UPDATE_GOLDEN=1 nim c -r tests/tcli.nim
import std/[unittest, os, strutils, sequtils, algorithm]
import eversince, eversince/[cli, catalog, picture]
import ../examples/desk/desk

let root = currentSourcePath().parentDir / ".."
let deskEm = root / "examples" / "desk" / "desk.em"
let deskScenarios = root / "examples" / "desk" / "scenarios.jsonl"
let work = getTempDir() / "eversince-tcli"

proc lf(s: string): string = s.replace("\r\n", "\n")

proc golden(name, got: string) =
  let path = root / "tests" / "golden" / name
  if getEnv("EVERSINCE_UPDATE_GOLDEN").len > 0: writeFile(path, got)
  check lf(readFile(path)) == got

proc run(args: seq[string], app = App()): tuple[code: int, outp, errp: string] =
  var s: Sink
  result.code = dispatch(args, s, app)
  result.outp = s.outp
  result.errp = s.errp

proc deskApp(): App = appOf[DeskApp](deskAppCatalog)

proc write(name, text: string): string =
  createDir(work)
  result = work / name
  writeFile(result, text)

let base = """
screen S | commands Go
command Go x:int | reads V | produces Done | refuses no
event Done x:int
view V n:int | consumes Done
query Q | reads V | returns int
screen S2 | queries Q
slice go : S -> Go -> Done -> V -> Q -> S2
"""

suite "catalog":
  test "the desk catalogue is the golden file":
    let text = readFile(deskEm)
    golden "desk.catalog.txt", catalogText(parseModel(text), text)

  test "it starts with the size line and groups blocks by kind, sorted by name":
    let c = catalogText(parseModel(base))
    check c.startsWith("# eversince catalog\nsize: 1 commands, 1 events")
    let at = proc (s: string): int = c.find(s)
    check at("## screens (2)") < at("## commands (1)")
    check at("## commands (1)") < at("## events (1)")
    check at("## views (1)") < at("## queries (1)")
    check at("## queries (1)") < at("## slices (1)")
    check "- Go(x:int) - reads V; produces Done; refuses no; on screen S" in c
    check "- Done(x:int) - produced by Go; consumed by V" in c

  test "the order of lines in the model file does not change it":
    let text = readFile(deskEm)
    let lines = text.splitLines
    let shuffled = lines.reversed.join("\n")
    check catalogText(parseModel(text)) == catalogText(parseModel(shuffled))

  test "a comment at the end of a block line is that block's meaning":
    let text = "event Said text:string # what the producer said\nevent Heard text:string\n"
    let c = catalogText(parseModel(text), text)
    check "- Said(text:string) - what the producer said" in c
    check "- Heard(text:string)\n" in c

  test "a kind outside the vocabulary is shown, not hidden":
    let text = "widget W a:int\n"
    check "## widget (not in the vocabulary) (1)" in catalogText(parseModel(text), text)

  test "the output has no carriage returns and ends with one newline":
    let c = catalogText(parseModel(base))
    check '\r' notin c
    check c.endsWith("\n") and not c.endsWith("\n\n")

suite "picture layout":
  test "the desk picture is the golden file":
    golden "desk.svg", render(parseModel(readFile(deskEm)))

  test "the same model gives the same bytes, whatever the order of the blocks":
    let text = readFile(deskEm)
    let m = parseModel(text)
    check render(m) == render(m)
    let blocksReversed = text.splitLines.filterIt(not it.startsWith("slice")).reversed.join("\n") & "\n" &
      text.splitLines.filterIt(it.startsWith("slice")).join("\n")
    check render(parseModel(blocksReversed)) == render(m)

  test "slices are grouped by their screen, background work last":
    let svg = render(parseModel(readFile(deskEm) & "slice only the runner : TurnRunner -> EndTurn -> TurnEnded\n"))
    let a = svg.find("id=\"group-chatpanel\"")
    let b = svg.find("id=\"group-stepspanel\"")
    let c = svg.find("id=\"group-background-work\"")
    check a >= 0 and b > a and c > b
    check svg.count("<g transform=") == 7

  test "a slice of more than maxCols steps wraps onto a second row":
    proc slice(n: int): string =
      "screen A | commands C0\ncommand C0 | produces E0\nevent E0\nslice long : " &
        toSeq(0 ..< n).mapIt(if it mod 2 == 0: "A" else: "C0").join(" -> ")
    check "<path class=\"em-edge\"" notin render(parseModel(slice(maxCols)))
    let wrapped = render(parseModel(slice(maxCols + 1)))
    check "<path class=\"em-edge\"" in wrapped
    # the second row adds three lanes of labels
    check wrapped.count("who acts") == 2

  test "a long name is split at a capital letter, and the full line is in a tooltip":
    let name = "ConversationClearedAndArchivedForGoodMeasureEvent"
    let m = parseModel("event " & name & " x:int\nslice s : " & name)
    let svg = render(m)
    check name notin svg.replace("<title>event " & name & " x:int</title>", "")
    check "<title>event " & name & " x:int</title>" in svg

  test "a step that is not in the model file is drawn as missing, with its name":
    let svg = render(parseModel("slice s : Ghost"))
    check "em-missing" in svg
    check "Ghost" in svg
    check "NOT IN MODEL" in svg

  test "a model without slices still gives a valid picture":
    let svg = render(parseModel("event A x:int\n"))
    check svg.startsWith("<svg") and svg.strip.endsWith("</svg>")
    check "viewBox=\"0 0 " in svg and "no slices yet" in svg

  test "names are escaped":
    let svg = render(parseModel("slice a<b&c : X"))
    check "a&lt;b&amp;c" in svg
    check "a<b" notin svg

  test "the style has no custom properties, so any SVG renderer can draw it":
    check "var(--" notin render(parseModel(base))
    check "prefers-color-scheme:dark" in render(parseModel(base))

suite "check report":
  test "a model that matches its code is ok":
    let m = parseModel(base)
    let r = checkReport(m, m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical), true, false)
    check r.exit == exitOk
    check "result: ok (0 errors, 0 warnings)" in r.text
    check "code: compared with the compiled blocks (4 blocks)" in r.text

  test "drift is an error with both lines, and the exit code is 1":
    let m = parseModel(base)
    let code = m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical).filterIt(not it.startsWith("event")) & "event Done x:string"
    let r = checkReport(m, code, true, false)
    check r.exit == exitFail
    check "error: model and code disagree about `event Done`" in r.text
    check "result: FAIL (1 error, 0 warnings)" in r.text

  test "a lint is a warning, and a failure under strict":
    let m = parseModel(base & "event Lonely a:int\n")
    let code = m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical)
    check checkReport(m, code, true, false).exit == exitOk
    let strict = checkReport(m, code, true, true)
    check strict.exit == exitFail
    check "warning: event Lonely is produced by no command" in strict.text
    check "strict" in strict.text.splitLines[^2]

  test "the same message is not printed twice":
    let m = parseModel("slice s : Ghost -> Ghost2\n")
    let r = checkReport(m, @[], false, false)
    check r.text.count("`Ghost` does not exist") == 1

  test "without code, the report says so":
    let r = checkReport(parseModel(base), @[], false, false)
    check "code: not compared (no --app)" in r.text

suite "exit codes":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)

  test "no arguments is a usage error and prints the usage on stderr":
    let r = run(@[])
    check r.code == exitUsage
    check "usage: eversince" in r.errp
    check r.outp == ""

  test "help and --help print the usage and exit 0":
    check run(@["help"]).code == exitOk
    check run(@["--help"]).outp.contains("exit codes:")
    check "usage: eversince catalog" in run(@["help", "catalog"]).outp

  test "every command has --help text that names the exit codes":
    for c in ["catalog", "check", "pic", "scenarios", "size"]:
      let r = run(@[c, "--help"])
      check r.code == exitOk
      check ("usage: eversince " & c) in r.outp
      check "exit codes:" in r.outp
      check r.errp == ""

  test "an unknown command, an unknown option or a missing argument is a usage error":
    check run(@["frobnicate"]).code == exitUsage
    check run(@["help", "frobnicate"]).code == exitUsage
    check run(@["catalog", deskEm, "--nope"]).code == exitUsage
    check run(@["catalog"]).code == exitUsage
    check run(@["catalog", deskEm, deskEm]).code == exitUsage
    check run(@["check", deskEm, "--app"]).code == exitUsage
    check run(@["pic"]).code == exitUsage
    check run(@["scenarios", deskScenarios]).code == exitUsage
    check "needs the app" in run(@["scenarios", deskScenarios]).errp

  test "a file that cannot be read is exit 3":
    for c in ["catalog", "check", "pic", "size"]:
      let r = run(@[c, work / "missing.em"])
      check r.code == exitCannot
      check "cannot read" in r.errp
    check run(@["scenarios", work / "missing.jsonl", "--app", "x"], deskApp()).code == exitCannot
    check run(@["pic", deskEm, work / "no" / "such" / "dir" / "o.svg"]).code == exitCannot

  test "a model file that does not parse is exit 1 and says what is wrong":
    let bad = write("bad.em", "slice no colon here\n")
    let r = run(@["check", bad])
    check r.code == exitFail
    check "does not parse" in r.errp
    check "slice line needs" in r.errp
    check run(@["catalog", bad]).code == exitFail

  test "catalog and size print and exit 0":
    check run(@["catalog", deskEm]).code == exitOk
    check run(@["size", deskEm]).outp == "size: 8 commands, 9 events, 2 views, 2 query/queries, 2 processors, 2 screens, 6 slices\n"

  test "check on the desk model alone is ok":
    let r = run(@["check", deskEm])
    check r.code == exitOk
    check "result: ok" in r.outp

  test "check against the compiled desk is ok, and against a drifted model is 1":
    let ok = run(@["check", deskEm, "--app", "desk.nim"], deskApp())
    check ok.code == exitOk
    check "compared with the compiled blocks (27 blocks)" in ok.outp
    check "against desk.nim" in ok.outp
    let drifted = write("drift.em", readFile(deskEm).replace("refuses staleStep", "refuses staleStep,gone"))
    let bad = run(@["check", drifted, "--app", "desk.nim"], deskApp())
    check bad.code == exitFail
    check "model and code disagree about `command EndStep`" in bad.outp

  test "check --strict fails on a lint":
    let m = write("lint.em", readFile(deskEm) & "event Lonely a:int\n")
    check run(@["check", m]).code == exitOk
    check run(@["check", m, "--strict"]).code == exitFail

  test "pic writes a file or stdout":
    let out1 = work / "o.svg"
    let r = run(@["pic", deskEm, out1])
    check r.code == exitOk
    check r.outp.startsWith("wrote ") and "6 slices" in r.outp
    check lf(readFile(out1)).startsWith("<svg")
    check run(@["pic", deskEm]).outp == readFile(out1)
    check run(@["pic", deskEm, "-"]).outp == readFile(out1)

suite "scenarios":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)

  test "the 20 desk scenarios pass, each on its own line":
    let r = run(@["scenarios", deskScenarios, "--app", "desk.nim"], deskApp())
    check r.code == exitOk
    check r.outp.count("PASS ") == 20
    check "FAIL" notin r.outp
    check "result: ok (20 passed, 0 failed)" in r.outp
    check "PASS   1  a message starts a turn" in r.outp

  test "a scenario that does not hold fails the run with the reason":
    let f = write("s.jsonl", """{"name":"wrong code","given":[],"when":{"command":"SendMessage","data":{"game":"cat","text":"  "}},"then":{"refused":"busy"}}
{"name":"right code","given":[],"when":{"command":"SendMessage","data":{"game":"cat","text":"  "}},"then":{"refused":"badMessage"}}
""")
    let r = run(@["scenarios", f, "--app", "desk.nim"], deskApp())
    check r.code == exitFail
    check "FAIL   1  wrong code" in r.outp
    check "expected refusal busy, got badMessage" in r.outp
    check "PASS   2  right code" in r.outp
    check "result: FAIL (1 passed, 1 failed)" in r.outp

  test "a bad line fails that line and the run goes on":
    let f = write("s.jsonl", "{not json\n" &
      """{"given":[],"then":{}}""" & "\n" &
      """{"name":"no then","given":[]}""" & "\n" &
      """{"name":"ok","given":[],"when":{"command":"StopTurn","data":{"game":"x"}},"then":{"refused":"noTurn"}}""" & "\n" &
      """{"name":"ok","given":[],"then":{}}""" & "\n" &
      """{"name":"no command","given":[],"when":{},"then":{}}""" & "\n" &
      "[1]\n\n")
    let r = run(@["scenarios", f, "--app", "desk.nim"], deskApp())
    check r.code == exitFail
    check "FAIL   1  line 1" in r.outp and "not valid JSON" in r.outp
    check "FAIL   2  line 2" in r.outp and "no name" in r.outp
    check "FAIL   3  no then" in r.outp and "no `then` object" in r.outp
    check "PASS   4  ok" in r.outp
    check "FAIL   5  ok" in r.outp and "repeats an earlier scenario" in r.outp
    check "`when` needs a command" in r.outp
    check "a scenario is a JSON object" in r.outp
    check "(1 passed, 6 failed)" in r.outp

  test "an exception inside the runner is a failure, not a crash":
    let f = write("s.jsonl", """{"name":"unknown view","given":[],"then":{"view":{"Nope":{"a":1}}}}""" & "\n")
    let r = run(@["scenarios", f, "--app", "desk.nim"], deskApp())
    check r.code == exitFail
    check "FAIL   1  unknown view" in r.outp

  test "with --model, names that are not in the model fail":
    let f = write("s.jsonl", """{"name":"a","given":[],"when":{"command":"Nope","data":{}},"then":{}}
{"name":"b","given":[{"kind":"Nope","data":{}}],"then":{}}
{"name":"c","given":[],"when":{"command":"StopTurn","data":{"game":"x"}},"then":{"refused":"madeUp"}}
{"name":"d","given":[],"then":{"view":{"Nope":{}}}}
""")
    let r = run(@["scenarios", f, "--app", "desk.nim", "--model", deskEm], deskApp())
    check r.code == exitFail
    check "command `Nope` is not a command in the model" in r.outp
    check "given event `Nope` is not an event in the model" in r.outp
    check "`madeUp` is not a refusal code of StopTurn (it lists: noTurn)" in r.outp
    check "view `Nope` is not a view in the model" in r.outp

  test "with --model, uncovered commands and refusal codes are notes, and a failure under --strict":
    let args = @["scenarios", deskScenarios, "--app", "desk.nim", "--model", deskEm]
    let r = run(args, deskApp())
    check r.code == exitOk
    check "note: command EndStep has no accepted scenario" in r.outp
    check "note: command EndStep has no scenario for refusal `staleStep`" in r.outp
    check "5 uncovered" in r.outp
    let strict = run(args & "--strict", deskApp())
    check strict.code == exitFail
    check "strict" in strict.outp.splitLines[^2]

  test "coverageNotes lists a command with every scenario as covered":
    let m = parseModel("command C | produces E | refuses a,b\nevent E\n")
    let text = """{"name":"1","given":[],"when":{"command":"C","data":{}},"then":{"events":[]}}
{"name":"2","given":[],"when":{"command":"C","data":{}},"then":{"refused":"a"}}
{"name":"3","given":[],"when":{"command":"C","data":{}},"then":{"refused":"b"}}
"""
    check coverageNotes(text, m).len == 0
    check coverageNotes(text.splitLines[0 .. 1].join("\n"), m) == @["command C has no scenario for refusal `b`"]

  test "the output does not depend on the machine: no absolute path appears":
    let r = run(@["scenarios", "examples/desk/scenarios.jsonl", "--app", "examples/desk/desk.nim"], deskApp())
    check root notin r.outp
