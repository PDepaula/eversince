## The command line, as a library: argument parsing, the five commands, their reports and their
## exit codes. `tools/eversince.nim` is a thin shell around `dispatch`; a test calls `dispatch`
## directly and reads what it wrote.
##
## Exit codes (a contract; `eversince --help` prints it):
##   0  ok
##   1  the thing checked is wrong: model and code disagree, a scenario failed, a file does not
##      parse, or a lint under --strict
##   2  usage error: unknown command or option, missing or surplus argument
##   3  could not run: a file cannot be read or written, the app does not build, nim is missing
##
## Everything printed is a function of the inputs: no clock, no absolute paths of the machine
## (a path is printed as given on the command line), no ordering that depends on a hash table.

import std/[strutils, sequtils, json, os, algorithm]
import ./[types, model, catalog, picture, runtime]

const
  exitOk* = 0
  exitFail* = 1
  exitUsage* = 2
  exitCannot* = 3

type
  Sink* = object
    ## What a run wrote: `main` copies it to the real streams, a test reads it.
    outp*, errp*: string

  ScenarioRun* = proc (sc: JsonNode): string {.nimcall.}
    ## "" when the scenario passes, else why not (`runScenario[A]`).

  App* = object
    ## What a build with the app's code in it offers the commands. Empty for the plain tool.
    loaded*: bool
    catalog*: seq[string]         ## one canonical line per block declared in code
    run*: ScenarioRun

  Options = object
    positional: seq[string]
    app, appType, model: string
    strict, help: bool

  CliError = object of CatchableError
    code: int

const
  exitCodesHelp = "\n" & """exit codes:
  0  ok (lints are printed; they only fail under --strict)
  1  the check failed: model and code disagree, a scenario failed, a file does not parse
  2  usage error: unknown command or option, missing or surplus argument
  3  could not run: a file cannot be read or written, the app does not build, nim is missing"""

  usageText = """usage: eversince <command> [options]

commands:
  catalog <model.em>              the blocks and what each one is, as a list to read (deterministic)
  check <model.em> [--app <app.nim>] [--strict]
                                  the model check; with --app also against the compiled code
  pic <model.em> [<out.svg>]      the model as an SVG, grouped by screen, one band per slice
  scenarios <file.jsonl> --app <app.nim> [--model <model.em>] [--strict]
                                  run the scenarios; print pass or fail for each
  size <model.em>                 the size line (counts of each block kind)
  help [<command>]                this text, or the text of one command

`eversince <command> --help` explains one command.
""" & exitCodesHelp

  helpTexts = [
    ("catalog", """usage: eversince catalog <model.em>

Print the catalogue of the model file: the size line, what each kind of block is, then every
block on one line (its fields, what it reads, produces, consumes or issues, and who uses it),
grouped by kind and sorted by name. An agent reads this at the start of a session instead of
opening source files. A comment at the end of a block line in the model file is added to that
block's line as its meaning.

The output depends only on the model file (not on the order of its lines), so a diff of two
catalogues shows a change in the model and nothing else.

""" & exitCodesHelp),
    ("check", """usage: eversince check <model.em> [--app <app.nim>] [--app-type <Name>] [--strict]

Run the model check and print a report: the size line, then every error and warning, then a
result line.
  without --app  checks the model against itself: every screen and slice names real blocks and
                 real edges, and lints find blocks that connect to nothing.
  with --app     also compares the model with the code. The tool builds a small program that
                 imports <app.nim> (it calls `sealModel`), reads the app's registry from it, and
                 compares both ways: a block the model has and the code lacks, the code has and
                 the model lacks, or both have and differ. If the build itself stops because the
                 app's own model file does not match, that is reported as drift too.
  --app-type     the app's type name, when the tool cannot find `sealModel(Name, ...)` in the file.
  --strict       warnings (lints) make the check fail.

Needs `nim` on the PATH when --app is given. The build takes a few seconds.

""" & exitCodesHelp),
    ("pic", """usage: eversince pic <model.em> [<out.svg>]

Draw the model file as an SVG (it needs no code). Slices are grouped under the first screen they pass through,
one band per slice, three lanes (who acts, requests and answers, facts). A slice longer than
""" & $maxCols & """ steps continues on a second row. Every box carries its block's line as a tooltip. The SVG has its
own style, light and dark. Without <out.svg>, or with `-`, the SVG goes to stdout.

The output depends only on the model file, so a diff of two pictures shows a change in the model.

""" & exitCodesHelp),
    ("scenarios", """usage: eversince scenarios <file.jsonl> --app <app.nim> [--app-type <Name>] [--model <model.em>] [--strict]

Run every scenario of the file (format: spec/11-scenarios.md) against the app's decisions and
folds, and print one line per scenario: PASS or FAIL, its number and name, and for a failure why.
The tool builds a small program that imports <app.nim>; it needs `nim` on the PATH.
  --model   also check each scenario against the model: its command and event kinds exist, its
            refusal code is one the command lists. Then it notes every command that has no
            accepted scenario and every refusal code that has none.
  --strict  those notes make the run fail.

A line that is not valid JSON, has no name or no `then`, or repeats an earlier name, fails.

""" & exitCodesHelp),
    ("size", """usage: eversince size <model.em>

Print the size line: how many commands, events, views, queries, processors, screens and slices
the model file holds.

""" & exitCodesHelp)]

proc fail(code: int, msg: string) {.noreturn.} =
  var e = newException(CliError, msg)
  e.code = code
  raise e

proc say(s: var Sink, text: string) = s.outp.add text & "\n"
proc warn(s: var Sink, text: string) = s.errp.add text & "\n"

proc helpFor*(command: string): string =
  for (name, text) in helpTexts:
    if name == command: return text

proc parseOptions(args: seq[string]): Options =
  var i = 0
  proc value(flag: string): string =
    if i + 1 >= args.len or args[i + 1].startsWith("--"): fail(exitUsage, flag & " needs a value")
    inc i
    args[i]
  while i < args.len:
    let a = args[i]
    if a == "--help" or a == "-h": result.help = true
    elif a == "--strict": result.strict = true
    elif a == "--app": result.app = value(a)
    elif a == "--app-type": result.appType = value(a)
    elif a == "--model": result.model = value(a)
    elif a.startsWith("--app="): result.app = a[6 .. ^1]
    elif a.startsWith("--app-type="): result.appType = a[11 .. ^1]
    elif a.startsWith("--model="): result.model = a[8 .. ^1]
    elif a.startsWith("--"): fail(exitUsage, "unknown option " & a)
    else: result.positional.add a
    inc i

proc readText(path: string): string =
  try: readFile(path)
  except IOError: fail(exitCannot, "cannot read " & path)

proc loadModel*(path: string): tuple[model: Model, text: string] =
  result.text = readText(path)
  try: result.model = parseModel(result.text)
  except ModelParseError as e: fail(exitFail, path & " does not parse: " & e.msg)

proc codeLines(m: Model): seq[string] =
  m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical)

# ---------------------------------------------------------------------------------- check

proc checkReport*(m: Model, code: seq[string], compared: bool, strict: bool): tuple[text: string, exit: int] =
  ## The report of a check: `compared` says whether `code` is the compiled code or the model itself.
  let (rawErrors, rawWarnings) = checkModel(m, code)
  let errors = rawErrors.deduplicate    # the same slice step can be reported from both of its ends
  let warnings = rawWarnings.deduplicate
  var lines = @["size: " & m.counts,
    (if compared: "code: compared with the compiled blocks (" & $code.len & " blocks)"
     else: "code: not compared (no --app); model checked against itself")]
  for e in errors: lines.add "error: " & e.strip(leading = false)
  for w in warnings: lines.add "warning: " & w
  let failed = errors.len > 0 or (strict and warnings.len > 0)
  lines.add (if failed: "result: FAIL" else: "result: ok") & " (" & $errors.len & " error" &
    (if errors.len == 1: "" else: "s") & ", " & $warnings.len & " warning" & (if warnings.len == 1: "" else: "s") &
    (if strict and warnings.len > 0: ", strict" else: "") & ")"
  result = (lines.join("\n") & "\n", if failed: exitFail else: exitOk)

proc runCheck(o: Options, app: App, s: var Sink): int =
  if o.positional.len != 1: fail(exitUsage, "check needs one model file: eversince check <model.em>")
  let (m, _) = loadModel(o.positional[0])
  s.say "check: " & o.positional[0] & (if app.loaded and o.app.len > 0: " against " & o.app else: "")
  let (text, code) = checkReport(m, if app.loaded: app.catalog else: m.codeLines, app.loaded, o.strict)
  s.outp.add text
  code

# ------------------------------------------------------------------------------ scenarios

type ScenarioResult* = object
  line*: int          ## line of the file, 1-based
  name*: string
  ok*: bool
  why*: string

proc checkAgainstModel(sc: JsonNode, m: Model): string =
  ## What can be said about a scenario from the model file alone: the names it uses exist.
  let known = proc (kind, name: string): bool =
    m.blocks.anyIt(it.kind == kind and it.name == name)
  for g in sc{"given"}.getElems:
    let k = g{"kind"}.getStr
    if not known("event", k): return "given event `" & k & "` is not an event in the model"
  if sc.hasKey("when"):
    let c = sc["when"]{"command"}.getStr
    if not known("command", c): return "command `" & c & "` is not a command in the model"
    let want = sc["then"]{"refused"}
    if not want.isNil and want.kind == JString and want.getStr notin m.find(c).edge("refuses"):
      return "`" & want.getStr & "` is not a refusal code of " & c & " (it lists: " & m.find(c).edge("refuses").join(",") & ")"
    if not sc["then"]{"events"}.isNil:
      for e in sc["then"]["events"].getElems:
        if not known("event", e{"kind"}.getStr): return "expected event `" & e{"kind"}.getStr & "` is not an event in the model"
        if e{"kind"}.getStr notin m.find(c).edge("produces"):
          return "command " & c & " does not produce " & e{"kind"}.getStr
  if not sc["then"]{"view"}.isNil:
    for name, _ in sc["then"]["view"]:
      if not known("view", name): return "view `" & name & "` is not a view in the model"

proc runScenarios*(text: string, run: ScenarioRun, model: Model, withModel: bool): seq[ScenarioResult] =
  ## Every non-blank line of a scenarios file, run. A line that is not a scenario is a failure,
  ## not an exception, and the lines after it still run.
  var seen: seq[string]
  var n = 0
  for raw in text.splitLines:
    inc n
    if raw.strip.len == 0: continue
    var r = ScenarioResult(line: n)
    try:
      let sc = parseJson(raw)
      if sc.kind != JObject: fail(exitFail, "a scenario is a JSON object")
      r.name = sc{"name"}.getStr
      if not (sc.hasKey("name") and sc["name"].kind == JString and r.name.len > 0): fail(exitFail, "no name")
      if r.name in seen: fail(exitFail, "the name repeats an earlier scenario")
      seen.add r.name
      if not sc.hasKey("given") or sc["given"].kind != JArray: fail(exitFail, "no `given` list")
      if not sc.hasKey("then") or sc["then"].kind != JObject: fail(exitFail, "no `then` object")
      if sc.hasKey("when") and (sc["when"].kind != JObject or sc["when"]{"command"}.isNil): fail(exitFail, "`when` needs a command")
      if withModel:
        let why = checkAgainstModel(sc, model)
        if why.len > 0: fail(exitFail, why)
      let why = run(sc)
      r.ok = why.len == 0
      r.why = why
    except CliError as e:
      r.why = e.msg
    except JsonParsingError as e:
      r.why = "not valid JSON: " & e.msg.splitLines[0]
    except CatchableError as e:
      r.why = "could not run: " & e.msg
    result.add r

proc coverageNotes*(text: string, m: Model): seq[string] =
  ## Commands with no accepted scenario and refusal codes with no scenario (rule 5 of AGENTS.md).
  var accepted, refused: seq[string]       ## "Command" and "Command code"
  for raw in text.splitLines:
    if raw.strip.len == 0: continue
    try:
      let sc = parseJson(raw)
      let c = sc{"when"}{"command"}.getStr
      if c.len == 0 or sc{"then"}.isNil: continue
      let r = sc["then"]{"refused"}
      if not r.isNil and r.kind == JString: refused.add c & " " & r.getStr
      else: accepted.add c
    except CatchableError: discard
  for b in m.blocks.filterIt(it.kind == "command").sortedByIt(it.name):
    if b.name notin accepted: result.add "command " & b.name & " has no accepted scenario"
    for code in b.edge("refuses"):
      if (b.name & " " & code) notin refused: result.add "command " & b.name & " has no scenario for refusal `" & code & "`"

proc runScenariosCommand(o: Options, app: App, s: var Sink): int =
  if o.positional.len != 1: fail(exitUsage, "scenarios needs one file: eversince scenarios <file.jsonl> --app <app.nim>")
  if not app.loaded: fail(exitUsage, "scenarios needs the app: add --app <app.nim>")
  let text = readText(o.positional[0])
  var m: Model
  if o.model.len > 0: m = loadModel(o.model).model
  let results = runScenarios(text, app.run, m, o.model.len > 0)
  s.say "scenarios: " & o.positional[0] & " (" & $results.len & " scenarios" & (if o.model.len > 0: ", checked against " & o.model else: "") & ")"
  var failed = 0
  for i, r in results:
    let label = if r.name.len > 0: r.name else: "line " & $r.line
    s.say (if r.ok: "PASS " else: "FAIL ") & align($(i + 1), 3) & "  " & label
    if not r.ok:
      inc failed
      s.say "          " & r.why
  var notes: seq[string]
  if o.model.len > 0: notes = coverageNotes(text, m)
  for n in notes: s.say "note: " & n
  let strictFail = o.strict and notes.len > 0
  s.say "result: " & (if failed > 0 or strictFail: "FAIL" else: "ok") & " (" & $(results.len - failed) & " passed, " & $failed &
    " failed" & (if o.model.len > 0: ", " & $notes.len & " uncovered" else: "") & (if strictFail: ", strict" else: "") & ")"
  if failed > 0 or strictFail: exitFail else: exitOk

# ----------------------------------------------------------------------- the other commands

proc runCatalog(o: Options, s: var Sink): int =
  if o.positional.len != 1: fail(exitUsage, "catalog needs one model file: eversince catalog <model.em>")
  let (m, text) = loadModel(o.positional[0])
  s.outp.add catalogText(m, text)
  exitOk

proc runSize(o: Options, s: var Sink): int =
  if o.positional.len != 1: fail(exitUsage, "size needs one model file: eversince size <model.em>")
  s.say "size: " & loadModel(o.positional[0]).model.counts
  exitOk

proc runPic(o: Options, s: var Sink): int =
  if o.positional.len notin 1 .. 2: fail(exitUsage, "pic needs a model file and optionally an output file: eversince pic <model.em> [<out.svg>]")
  let m = loadModel(o.positional[0]).model
  let svg = render(m)
  if o.positional.len == 1 or o.positional[1] == "-":
    s.outp.add svg
  else:
    try: writeFile(o.positional[1], svg)
    except IOError: fail(exitCannot, "cannot write " & o.positional[1])
    s.say "wrote " & o.positional[1] & " (" & $svg.len & " bytes) for " & m.counts
  exitOk

# ---------------------------------------------------------------------------------- dispatch

const commandNames = ["catalog", "check", "pic", "scenarios", "size"]

proc needsApp*(args: seq[string]): bool =
  ## True when these arguments ask for a comparison with compiled code that only a build with the
  ## app in it can give: `check` or `scenarios` with `--app`.
  try:
    args.len > 0 and args[0] in ["check", "scenarios"] and parseOptions(args[1 .. ^1]).app.len > 0 and
      not parseOptions(args[1 .. ^1]).help
  except CliError: false

proc dispatch*(args: seq[string], s: var Sink, app = App()): int =
  ## Runs one command line (without the program name) and returns the exit code.
  try:
    if args.len == 0:
      s.warn usageText
      return exitUsage
    let cmd = args[0]
    if cmd in ["help", "-h", "--help"]:
      if args.len >= 2:
        let h = helpFor(args[1])
        if h.len == 0: fail(exitUsage, "no command named " & args[1])
        s.say h
      else:
        s.say usageText
      return exitOk
    if cmd notin commandNames: fail(exitUsage, "unknown command " & cmd)
    let o = parseOptions(args[1 .. ^1])
    if o.help:
      s.say helpFor(cmd)
      return exitOk
    case cmd
    of "catalog": runCatalog(o, s)
    of "check": runCheck(o, app, s)
    of "pic": runPic(o, s)
    of "scenarios": runScenariosCommand(o, app, s)
    else: runSize(o, s)
  except CliError as e:
    s.warn "eversince: " & e.msg
    if e.code == exitUsage: s.warn "try `eversince help`"
    e.code

proc flush*(s: Sink) =
  stdout.write s.outp
  stderr.write s.errp

proc appOf*[A](catalog: string): App =
  ## The hooks for an app type: pass the `<app>Catalog` constant that `sealModel` generates.
  App(loaded: true, catalog: catalog.splitLines.filterIt(it.len > 0), run: proc (sc: JsonNode): string = runScenario[A](sc))

proc runWithApp*[A](catalog: string) =
  ## The whole `main` of a program that has the app's code in it (the tool builds one for
  ## `--app`; an app may also have its own).
  var s: Sink
  let code = dispatch(commandLineParams(), s, appOf[A](catalog))
  s.flush
  quit code
