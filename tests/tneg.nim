## The eleven builds that must fail (docs/m0-evidence.md), as tests.
##
## Each case compiles a copy of the desk example with one deliberate mistake and asserts that the
## compiler stops, with a stable fragment of the error (the check's name or the names it points
## at, never the whole text, so the wording can improve). The unedited desk must still build.
##
## The compile is `nim check`: every one of these checks runs during semantic analysis, so
## nothing needs the C compiler and each build takes about half a second. Every compile has a
## time limit, so a hung compiler fails the test instead of stalling CI. The compiler is the one
## running this test (`getCurrentCompilerExe`), the work happens in a temp directory, and the
## repository is never written to.
import std/[unittest, os, osproc, strutils, atomics, sequtils]

const
  nimExe = getCurrentCompilerExe()
  root = currentSourcePath().parentDir.parentDir
  deskDir = root / "examples" / "desk"

const timeLimitMs {.intdefine: "negTimeLimitMs".} = 120_000  ## per compile; `-d:negTimeLimitMs=1` shows the limit working

type Outcome = object
  ok: bool        ## the compiler exited with 0
  timedOut: bool
  text: string    ## everything it printed

let work = getTempDir() / ("eversince-tneg-" & $getCurrentProcessId())
createDir work
var caseNo = 0

proc compilerPath(): string =
  if nimExe.len > 0 and fileExists(nimExe): nimExe else: findExe("nim")

proc runWithLimit(args: seq[string]): Outcome =
  ## Run the compiler, capture stdout and stderr together, kill it after `timeLimitMs`.
  ## The output goes to a file, not a pipe: on Windows a zero-length write by the compiler reads
  ## as end-of-stream and cut the captured text short. On Windows `poEvalCommand` hands the line
  ## straight to CreateProcess with no shell, so `cmd.exe /c` is spelled out; `cmd /c` drops the
  ## outermost quotes of its command line, so the whole line gets one more pair.
  let outFile = work / ("out-" & $caseNo & ".txt")
  var line = quoteShell(compilerPath())
  for a in args: line.add " " & quoteShell(a)
  line.add " > " & quoteShell(outFile) & " 2>&1"
  when defined(windows): line = "cmd.exe /c \"" & line & "\""
  let p = startProcess(line, options = {poEvalCommand, poUsePath})
  var finished: Atomic[bool]
  var expired: Atomic[bool]
  var watchdog: Thread[(pointer, ptr Atomic[bool], ptr Atomic[bool])]
  proc watch(a: (pointer, ptr Atomic[bool], ptr Atomic[bool])) {.thread.} =
    var waited = 0
    while waited < timeLimitMs and not a[1][].load:
      sleep 50
      waited += 50
    if not a[1][].load:
      a[2][].store true
      cast[Process](a[0]).kill()
  createThread(watchdog, watch, (cast[pointer](p), addr finished, addr expired))
  let code = p.waitForExit()   # returns when the compiler exits or is killed
  finished.store true
  joinThread watchdog
  p.close()
  result.text = if fileExists(outFile): readFile(outFile) else: ""
  result.timedOut = expired.load
  result.ok = code == 0 and not result.timedOut

proc replaceOnce(text, old, replacement: string): string =
  doAssert old in text, "test setup: `" & old & "` is not in desk.em any more, update tneg.nim"
  text.replace(old, replacement)

proc editLine(text, startsWith: string, change: proc (line: string): string): string =
  ## Change the one line that starts with `startsWith`; `""` from `change` deletes it.
  var lines = text.splitLines
  let i = lines.mapIt(it.startsWith(startsWith)).find(true)
  doAssert i >= 0, "test setup: no line starts with `" & startsWith & "` in desk.em, update tneg.nim"
  let fresh = change(lines[i])
  if fresh.len == 0: lines.delete i else: lines[i] = fresh
  lines.join("\n")

proc build(flags: seq[string] = @[], editModel: proc (text: string): string = nil): Outcome =
  ## Copy the desk example into a fresh directory, apply the edit to `desk.em`, compile it.
  inc caseNo
  let dir = work / $caseNo
  createDir dir
  copyFile(deskDir / "desk.nim", dir / "desk.nim")
  var model = readFile(deskDir / "desk.em")
  if editModel != nil: model = editModel(model)
  writeFile(dir / "desk.em", model)
  runWithLimit(@["check", "--hints:off", "--warnings:off", "--skipUserCfg:on", "--skipParentCfg:on",
                 "--path:" & (root / "src"), "--nimcache:" & (dir / "cache")] & flags & (dir / "desk.nim"))

template mustFail(outcome: Outcome, fragments: varargs[string]) =
  ## A template, not a proc: `check` must run inside the test body to mark that test failed.
  let o = outcome
  check not o.timedOut
  check not o.ok
  check "Error:" in o.text
  for f in fragments:
    if f notin o.text: echo "missing `", f, "` in the compiler output:\n", o.text
    check f in o.text

suite "the unedited desk builds":
  test "no flag, and strict mode":
    for flags in [newSeq[string](), @["-d:eversinceStrict"]]:
      let o = build(flags)
      if not o.ok: echo o.text
      check not o.timedOut
      check o.ok

suite "the code breaks a rule inside a block":
  test "1 negEmit: a command emits an event its `produces` line does not list":
    build(@["-d:negEmit"]).mustFail("StepEnded", "produces")

  test "2 negClock: a command's decide prints (a side effect)":
    build(@["-d:negClock"]).mustFail("decide", "side effects")

  test "3 negEnv: a command's decide reads the environment":
    build(@["-d:negEnv"]).mustFail("ReadEnvEffect")

  test "4 negView: a view's `on` handler reads the environment":
    build(@["-d:negView"]).mustFail("ReadEnvEffect")

  test "5 negQuery: a query changes a view":
    build(@["-d:negQuery"]).mustFail("immutable")

  test "6 negIssue: a processor issues a command its `issues` line does not list":
    build(@["-d:negIssue"]).mustFail("TurnRunner", "StartStep", "issues")

suite "the model file and the code disagree":
  test "7 a changed `produces`: model and code disagree about a command":
    build(editModel = proc (t: string): string =
      t.editLine("command SendMessage", proc (l: string): string =
        l.replaceOnce("produces MessageSent,TurnStarted", "produces MessageSent"))
    ).mustFail("does not match the code", "SendMessage")

  test "8 an added block: the model declares blocks the code lacks":
    build(editModel = proc (t: string): string =
      t & "\ncommand ArchiveGame game:string | reads Desk | produces GameArchived\n" &
          "event GameArchived game:string\n"
    ).mustFail("does not match the code", "ArchiveGame", "GameArchived")

  test "9 a deleted block: the code declares a block the model lacks":
    build(editModel = proc (t: string): string =
      t.editLine("event StopRequested", proc (l: string): string = "")
    ).mustFail("does not match the code", "StopRequested")

  test "10 a bogus slice: it claims edges the blocks do not have":
    build(editModel = proc (t: string): string =
      t & "\nslice bogus : StepsPanel -> SendMessage -> StepEnded -> Chat\n"
    ).mustFail("does not match the code", "bogus")

suite "strict mode":
  test "11 a command removed from its screen is on no screen":
    build(@["-d:eversinceStrict"], proc (t: string): string =
      t.editLine("screen StepsPanel", proc (l: string): string =
        l.replaceOnce(" | commands StartStep", ""))
    ).mustFail("strict", "StartStep", "no screen")

removeDir work
