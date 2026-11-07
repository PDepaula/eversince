## The conformance runner: runs the language-neutral fixtures in spec/fixtures/ against this kit.
## The fixtures are plain data (JSON lines, model files, logs) that any kit can read unchanged;
## their format is in spec/fixtures/README.md. Nothing here is specific to a fixture, so adding a
## line to a fixture file adds a test.
import std/[unittest, os, strutils, sequtils, json]
import eversince
import ../examples/desk/desk

let
  root = currentSourcePath().parentDir / ".." / "spec" / "fixtures"
  work = getTempDir() / "eversince-tconform"

# -- reading fixture files ---------------------------------------------------------------------

proc jsonLines(path: string): seq[JsonNode] =
  ## One JSON object per line; blank lines are ignored.
  for line in lines(path):
    if line.strip.len > 0: result.add parseJson(line)

proc modelText(c: JsonNode, dir: string): string =
  ## A fixture's model text: a `file` (relative to the manifest), or `lines` joined by newlines.
  if c.hasKey("file"): return readFile(dir / c["file"].getStr)
  let ls = c["lines"].getElems.mapIt(it.getStr)
  if ls.len == 0: "" else: ls.join("\n") & "\n"

proc bare(raw: string): string = raw.split('#')[0].strip ## a model line without its comment

# -- comparing a parsed model with what a fixture expects ---------------------------------------

proc blocksJson(m: Model): JsonNode =
  result = newJArray()
  for b in m.blocks:
    var edges = newJArray()
    for e in b.edges: edges.add %*{"key": e.key, "values": e.vals}
    result.add %*{"kind": b.kind, "name": b.name, "fields": b.fields, "edges": edges}

proc slicesJson(m: Model): JsonNode =
  result = newJArray()
  for s in m.slices: result.add %*{"title": s.name, "steps": s.steps}

proc countOf(m: Model, kind: string): int =
  if kind == "slice": m.slices.len else: m.blocks.countIt(it.kind == kind)

# -- matching the check's findings with the blocks a fixture says they concern ------------------

proc mentions(msg, name: string): bool =
  ## The finding names the block: as a whole word for a block, as a substring for a slice title
  ## (which may contain spaces). A kit's wording is its own; its findings must name what they concern.
  if ' ' in name: return name in msg
  const word = {'a'..'z', 'A'..'Z', '0'..'9', '_'}
  var i = msg.find(name)
  while i >= 0:
    let before = i == 0 or msg[i - 1] notin word
    let after = i + name.len >= msg.len or msg[i + name.len] notin word
    if before and after: return true
    i = msg.find(name, i + 1)

proc matchAll(msgs: seq[string], concerns: seq[JsonNode], used: seq[bool], at: int): bool =
  ## Every concern is matched by a different finding (a small search; fixtures list few).
  if at == concerns.len: return true
  for i, m in msgs:
    if not used[i] and m.mentions(concerns[at]["name"].getStr):
      var next = used
      next[i] = true
      if matchAll(msgs, concerns, next, at + 1): return true

proc concernsMatch(msgs: seq[string], concerns: seq[JsonNode]): bool =
  ## There are exactly as many findings as concerns, and each concern has its own finding.
  msgs.len == concerns.len and matchAll(msgs, concerns, newSeq[bool](msgs.len), 0)

# -- model file parsing ------------------------------------------------------------------------

suite "fixtures: model file parsing":
  let dir = root / "model"
  for c in jsonLines(dir / "parse.jsonl"):
    test c["name"].getStr:
      let text = modelText(c, dir)
      let then = c["then"]
      if then.hasKey("fails"):
        let wanted = text.splitLines[then["fails"]["concerns"]["line"].getInt - 1].bare
        var message = ""
        try: discard parseModel(text)
        except Exception as e: message = e.msg
        check message.len > 0 # parsing failed
        check wanted in message # and it names the offending line
      else:
        let m = parseModel(text)
        if then.hasKey("blocks"): check blocksJson(m) == then["blocks"]
        if then.hasKey("slices"): check slicesJson(m) == then["slices"]
        if then.hasKey("canonical"): check m.blocks.mapIt(it.canonical) == then["canonical"].getElems.mapIt(it.getStr)
        if then.hasKey("counts"):
          for kind, n in then["counts"]: check m.countOf(kind) == n.getInt

# -- model and code pairs ----------------------------------------------------------------------

suite "fixtures: model check":
  let dir = root / "model"
  var names: seq[string]
  for c in jsonLines(dir / "check.jsonl"):
    names.add c["name"].getStr
    test c["name"].getStr:
      let m = parseModel(modelText(c, dir))
      let code = c["code"].getElems.mapIt(it.getStr)
      # the fixture itself is sound: each code line is canonical, and each block it says a finding
      # concerns exists, with that kind, in the model or the code
      let inCode = parseModel(code.join("\n")).blocks
      check inCode.mapIt(it.canonical) == code
      var concerns: seq[JsonNode]
      for key in ["fails", "lints"]:
        if c["then"].hasKey(key): concerns.add c["then"][key].getElems
      for k in concerns:
        let (kind, name) = (k["kind"].getStr, k["name"].getStr)
        if kind == "slice": check m.slices.anyIt(it.name == name)
        else: check (m.blocks & inCode).anyIt(it.kind == kind and it.name == name)
      let r = checkModel(m, code)
      if c["then"].hasKey("fails"):
        check r.errors.concernsMatch(c["then"]["fails"].getElems)
      else:
        check c["then"]["ok"].getBool
        check r.errors.len == 0
      if c["then"].hasKey("lints"):
        check r.warnings.concernsMatch(c["then"]["lints"].getElems)
  test "names in check.jsonl are unique":
    check names.deduplicate.len == names.len

# -- the log -----------------------------------------------------------------------------------

proc envJson(e: Envelope): JsonNode = %*{"seq": e.seq, "at": e.at, "kind": e.kind, "data": e.data}

proc readLog(path: string): seq[Envelope] =
  ## Reads a log as a reader of an existing file does: the file is put in place after the store
  ## is opened, so what is tested is `load`'s own handling of a torn tail, not the clean-up that
  ## `openFileStore` does for a writer.
  createDir(work)
  let tmp = work / "read.jsonl"
  removeFile(tmp)
  let s = openFileStore(tmp)
  defer: s.close()
  writeFile(tmp, readFile(path))
  s.load

suite "fixtures: event log":
  let dir = root / "log"
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)
  for c in jsonLines(dir / "cases.jsonl"):
    test c["name"].getStr:
      let path = dir / c["log"].getStr
      let then = c["then"]
      if c.hasKey("append"):
        # a writer that opens the log and appends one event: the file ends up with these bytes
        let tmp = work / "append.jsonl"
        copyFile(path, tmp)
        let s = openFileStore(tmp)
        let a = c["append"]
        s.append([Envelope(seq: a["seq"].getBiggestInt, at: a["at"].getBiggestInt, kind: a["kind"].getStr, data: a["data"])])
        s.close()
        check readFile(tmp) == readFile(dir / then["file"].getStr)
      elif then.hasKey("fails"):
        var failed = false
        try: discard readLog(path)
        except CatchableError: failed = true
        check failed
        # the fixture's claim is true: line N is not an envelope, and the others are
        let n = then["fails"]["concerns"]["line"].getInt
        let fileLines = readFile(path).splitLines
        for i in 0 ..< fileLines.len:
          let line = fileLines[i]
          if line.len == 0: continue
          var ok = true
          try: discard fromLine(line)
          except CatchableError: ok = false
          check ok == (i + 1 != n)
      else:
        let events = readLog(path)
        check events.len == then["count"].getInt
        if then.hasKey("events"): check events.map(envJson) == then["events"].getElems
        if then.hasKey("last"): check envJson(events[^1]) == then["last"]
        if then.hasKey("sameAs"): check events.map(envJson) == readLog(dir / then["sameAs"].getStr).map(envJson)
        if then.hasKey("canonical"):
          # a writer writes the one form: each line read, written again, is the same bytes
          var complete = readFile(path).splitLines.filterIt(it.len > 0)
          check complete.len == events.len
          for i, e in events: check e.toLine == complete[i]
        if then.hasKey("view"):
          check c["app"].getStr == "desk"
          var app: DeskApp
          for e in events: apply(app, e)
          let all = %app
          for name, want in then["view"]:
            let got = all{lowerFirst(name)}
            for key, val in want: check got{key} == val

# -- scenarios ---------------------------------------------------------------------------------

proc scenarioNames(file: string): seq[string] = jsonLines(file).mapIt(it["name"].getStr)

suite "fixtures: scenarios":
  let
    pass = [root / "scenarios" / "pass.jsonl", currentSourcePath().parentDir / ".." / "examples" / "desk" / "scenarios.jsonl"]
    fail = root / "scenarios" / "fail.jsonl"
  for file in pass:
    for sc in jsonLines(file):
      test "passes: " & sc["name"].getStr:
        check runScenario[DeskApp](sc) == ""
  for sc in jsonLines(fail):
    test "fails: " & sc["name"].getStr:
      check runScenario[DeskApp](sc) != ""
  test "scenario names are unique in their file":
    for file in @pass & fail:
      let names = scenarioNames(file)
      check names.len > 0
      check names.deduplicate.len == names.len
