## A log that forgets: the fixtures in spec/fixtures/forget/ (plain data any kit reads) and what
## only this kit's API has (the clean hook, errors, replay after forgetting). Format of the
## fixtures: spec/fixtures/README.md. Rules: spec/14-forgetting.md.
import std/[unittest, os, strutils, json, sequtils, algorithm]
import eversince
import ../examples/desk/desk

let
  root = currentSourcePath().parentDir / ".." / "spec" / "fixtures" / "forget"
  work = getTempDir() / "eversince-tforget"

proc jsonLines(path: string): seq[JsonNode] =
  for line in lines(path):
    if line.strip.len > 0: result.add parseJson(line)

proc envelope(a: JsonNode): Envelope =
  Envelope(seq: a["seq"].getBiggestInt, at: a["at"].getBiggestInt, kind: a["kind"].getStr, data: a["data"])

proc byField(field: string): StreamOf =
  ## A stream is the string in `data.<field>`; an event without one belongs to no stream.
  result = proc (e: Envelope): string = e.data{field}.getStr

proc byGame(): StreamOf = byField("game")

suite "fixtures: forgetting":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)
  var names: seq[string]
  for c in jsonLines(root / "cases.jsonl"):
    names.add c["name"].getStr
    test c["name"].getStr:
      let tmp = work / "log.jsonl"
      copyFile(root / c["log"].getStr, tmp)
      let cap = if c.hasKey("cap"): c["cap"]["bytes"].getInt else: 0
      let s = openFileStore(tmp, streamOf = byField(c["stream"]["field"].getStr), maxStreamBytes = cap)
      for step in c{"steps"}.getElems:
        if step.hasKey("forget"):
          let which = step["forget"]
          for name in (if which.kind == JString: @[which.getStr] else: which.getElems.mapIt(it.getStr)):
            s.forget(name)
        else:
          s.append([envelope(step["append"])])
      s.close()
      check readFile(tmp) == readFile(root / c["then"]["file"].getStr)
  test "names in cases.jsonl are unique":
    check names.deduplicate.len == names.len

suite "file store: forgetting":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)
  proc desk16(): string =
    let tmp = work / "desk.jsonl"
    copyFile(root / ".." / "log" / "valid-16.jsonl", tmp)
    tmp

  test "a store with no streams cannot forget":
    let s = openFileStore(work / "a.jsonl")
    expect CatchableError: s.forget("cat")
    s.close()
    var m = MemStore()
    expect CatchableError: m.forget("cat")

  test "the empty string names no stream":
    let s = openFileStore(work / "a.jsonl", streamOf = byGame())
    expect ValueError: s.forget("")
    s.close()

  test "a cap needs streams":
    expect ValueError: discard openFileStore(work / "a.jsonl", maxStreamBytes = 100)

  test "the memory store forgets as the file store does":
    let tmp = desk16()
    let f = openFileStore(tmp, streamOf = byGame())
    let m = MemStore(streamOf: byGame())
    m.append(f.load)
    for name in ["dog", "cat", "fox"]:
      f.forget(name)
      m.forget(name)
      check m.load.map(toLine) == f.load.map(toLine)
    f.close()

  test "a store base that cannot forget says so, not silently":
    type Plain = ref object of Store
    expect CatchableError: Plain().forget("cat")

  test "the next position after forgetting is the next after the last the log ever held":
    let tmp = desk16()
    let s = openFileStore(tmp, streamOf = byGame())
    s.forget("dog") # holds events 11 to 16, the last
    s.close()
    var rt = replay[DeskApp](openFileStore(tmp, streamOf = byGame()))
    check rt.seq == 16
    rt.clock = proc (): int64 = 1_700_000_020_000'i64
    check not rt.execute("SendMessage", %*{"game": "fox", "text": "hello"}).refused
    let fresh = rt.store.load.filterIt(it.seq > 16)
    check fresh.len > 0
    check fresh.mapIt(it.seq) == toSeq(17'i64 .. rt.seq) # the next positions, none reused
    rt.store.close()

  test "a view of a forgotten stream is gone after replay, the others are as they were":
    let tmp = desk16()
    let before = replay[DeskApp](openFileStore(tmp))
    before.store.close()
    let s = openFileStore(tmp, streamOf = byGame())
    s.forget("cat")
    s.close()
    let after = replay[DeskApp](openFileStore(tmp))
    after.store.close()
    check before.app.chat.lines.filterIt(it.game == "cat").len > 0
    check after.app.chat.lines.filterIt(it.game == "cat").len == 0
    check after.app.chat.lines.filterIt(it.game == "dog") == before.app.chat.lines.filterIt(it.game == "dog")

  test "a log that forgot is read again by a fresh store, and appending goes on":
    let tmp = desk16()
    let s = openFileStore(tmp, streamOf = byGame())
    s.forget("cat")
    s.append([Envelope(seq: 17, at: 1, kind: "Said", data: %*{"game": "dog", "turn": 3, "text": "x"})])
    s.close()
    let again = openFileStore(tmp)
    check again.load.mapIt(it.seq) == @[7'i64, 9, 11, 12, 13, 14, 15, 16, 17]
    again.close()

  test "a temporary file a crashed rewrite left behind is removed, the log is as it was":
    let tmp = desk16()
    writeFile(tmp & ".tmp", """{"seq":1,"at":1,"kind":"Sai""")
    let s = openFileStore(tmp, streamOf = byGame())
    check not fileExists(tmp & ".tmp")
    check s.load.len == 16
    s.close()

  test "a rewrite leaves no temporary file":
    let tmp = desk16()
    let s = openFileStore(tmp, streamOf = byGame())
    s.forget("cat")
    check not fileExists(tmp & ".tmp")
    s.close()

  test "an incomplete line in the middle stops a rewrite and the file is not changed":
    let tmp = work / "bad.jsonl"
    var text = readFile(root / ".." / "log" / "torn-middle.jsonl")
    writeFile(tmp, text)
    let s = openFileStore(tmp, streamOf = byGame())
    expect CatchableError: s.forget("cat")
    s.append([Envelope(seq: 17, at: 1, kind: "Said", data: %*{"game": "cat"})]) # the store still works
    s.close()
    check readFile(tmp).startsWith(text)

suite "file store: size cap":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)
  test "a chat that keeps going stays within its cap, newest events kept":
    let tmp = work / "chat.jsonl"
    let s = openFileStore(tmp, streamOf = byGame(), maxStreamBytes = 2000)
    var biggest = 0
    for i in 1 .. 300:
      let g = if i mod 3 == 0: "dog" else: "cat"
      s.append([Envelope(seq: i, at: i, kind: "Said", data: %*{"game": g, "turn": 1, "text": "line " & $i})])
      for game in ["cat", "dog"]:
        let bytes = s.load.filterIt(it.data["game"].getStr == game).mapIt(it.toLine.len + 1).foldl(a + b, 0)
        biggest = max(biggest, bytes)
    check biggest <= 2000
    let kept = s.load
    check kept[^1].seq == 300
    # in order, and each stream's newest events are the ones that stayed
    check kept.mapIt(it.seq) == kept.mapIt(it.seq).sorted
    check kept.filterIt(it.data["game"].getStr == "cat").len > 10
    s.close()

  test "the cap counts the cleaned line, not the line given":
    let tmp = work / "clean.jsonl"
    let s = openFileStore(tmp, streamOf = byGame(), maxStreamBytes = 1000,
      clean = proc (e: Envelope): Envelope = Envelope(seq: e.seq, at: e.at, kind: e.kind, data: %*{"game": e.data["game"], "text": "x"}))
    for i in 1 .. 10:
      s.append([Envelope(seq: i, at: i, kind: "Said", data: %*{"game": "cat", "text": repeat("y", 1000)})])
    check s.load.len == 10 # ten small lines fit; the long lines would not
    s.close()

  test "a capped log a crash cut in the middle of a line is read and appended to":
    let tmp = work / "torn.jsonl"
    copyFile(root / ".." / "log" / "torn-tail.jsonl", tmp)
    let s = openFileStore(tmp, streamOf = byGame(), maxStreamBytes = 100_000)
    check s.load.len == 16
    s.append([Envelope(seq: 17, at: 1, kind: "Said", data: %*{"game": "cat"})])
    check s.load.len == 17
    s.close()

suite "file store: clean hook":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)
  proc redact(e: Envelope): Envelope =
    result = e
    if e.data.hasKey("text"):
      result.data = copy(e.data)
      result.data["text"] = %e.data["text"].getStr.replace("sk-secret", "[removed]")

  test "an event is stored as the hook returns it, and the caller's event is not changed":
    let tmp = work / "clean.jsonl"
    let s = openFileStore(tmp, clean = redact)
    let e = Envelope(seq: 1, at: 1, kind: "Said", data: %*{"game": "cat", "text": "key sk-secret here"})
    s.append([e])
    s.close()
    check "sk-secret" notin readFile(tmp)
    check "[removed]" in readFile(tmp)
    check e.data["text"].getStr == "key sk-secret here"

  test "the hook runs on events that are appended, not on events that are read":
    let tmp = work / "old.jsonl"
    writeFile(tmp, """{"seq":1,"at":1,"kind":"Said","data":{"game":"cat","text":"sk-secret"}}""" & "\n")
    let s = openFileStore(tmp, clean = redact)
    check s.load[0].data["text"].getStr == "sk-secret"
    s.close()

  test "a hook that changes seq, at or kind is refused and nothing is written":
    let tmp = work / "bad.jsonl"
    let s = openFileStore(tmp, clean = proc (e: Envelope): Envelope =
      result = e
      result.kind = "Other")
    expect ValueError: s.append([Envelope(seq: 1, at: 1, kind: "Said", data: %*{})])
    check readFile(tmp) == ""
    s.close()

  test "every event of one append goes through the hook":
    let tmp = work / "many.jsonl"
    let s = openFileStore(tmp, clean = redact)
    s.append([Envelope(seq: 1, at: 1, kind: "Said", data: %*{"text": "sk-secret"}),
              Envelope(seq: 2, at: 1, kind: "Said", data: %*{"text": "a sk-secret b"})])
    s.close()
    check readFile(tmp).count("[removed]") == 2
