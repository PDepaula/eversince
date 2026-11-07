## The desk example: its 20 scenarios, and replay giving the same state from the memory store and
## the JSON-lines store, including a log whose last line was cut short.
import std/[unittest, os, strutils, hashes]
import eversince
import ../examples/desk/desk

let scenarioFile = currentSourcePath().parentDir / ".." / "examples" / "desk" / "scenarios.jsonl"
let work = getTempDir() / "eversince-tdesk"

proc stateHash(app: DeskApp): string = toHex(hash($(%app)).int, 16)

proc script(rt: var Runtime[DeskApp]) =
  var tick = 1_700_000_000_000'i64
  rt.clock = proc (): int64 = tick
  runAgent = proc (game, text: string): seq[string] = @["On it.", "Done."]
  runStep = proc (game, kind: string): int = (if kind == "check": 0 else: 1)
  for (name, data) in [
      ("SendMessage", %*{"game": "cat", "text": "make the cat jump higher"}),
      ("StartStep", %*{"game": "cat", "kind": "check", "message": ""}),
      ("StartStep", %*{"game": "cat", "kind": "save", "message": ""}),
      ("StartStep", %*{"game": "cat", "kind": "save", "message": "higher jump"}),
      ("PickAgent", %*{"game": "cat", "agent": "codex"}),
      ("PickAgent", %*{"game": "cat", "agent": "gemini"}),
      ("SendMessage", %*{"game": "cat", "text": "  "}),
      ("SendMessage", %*{"game": "dog", "text": "add a bark"}),
      ("NewConversation", %*{"game": "dog"}),
      ("StopTurn", %*{"game": "cat"})]:
    tick += 1000
    discard rt.execute(name, data)

suite "desk scenarios":
  test "all scenarios in scenarios.jsonl pass":
    var n = 0
    for line in lines(scenarioFile):
      if line.strip.len == 0: continue
      let sc = parseJson(line)
      let why = runScenario[DeskApp](sc)
      check why == ""
      inc n
    check n == 20

suite "replay":
  setup:
    removeDir(work)
    createDir(work)
  teardown:
    removeDir(work)

  test "the script gives 16 events and a state a replay reproduces (memory)":
    var rt = Runtime[DeskApp](store: MemStore())
    script(rt)
    check rt.seq == 16
    let again = replay[DeskApp](rt.store)
    check again.seq == 16
    check stateHash(again.app) == stateHash(rt.app)

  test "the file store replays to the same state as the memory store":
    var mem = Runtime[DeskApp](store: MemStore())
    script(mem)
    let path = work / "desk.jsonl"
    var rt = Runtime[DeskApp](store: openFileStore(path))
    script(rt)
    rt.store.close()
    let again = replay[DeskApp](openFileStore(path))
    again.store.close()
    check again.seq == 16
    check stateHash(again.app) == stateHash(mem.app)

  test "the log is one JSON line per event with seq, at, kind and data":
    let path = work / "desk.jsonl"
    var rt = Runtime[DeskApp](store: openFileStore(path))
    script(rt)
    rt.store.close()
    let first = readFile(path).splitLines[0]
    check first == """{"seq":1,"at":1700000001000,"kind":"MessageSent","data":{"game":"cat","text":"make the cat jump higher"}}"""

  test "a half-written last line is skipped on load":
    let path = work / "desk.jsonl"
    var rt = Runtime[DeskApp](store: openFileStore(path))
    script(rt)
    let live = stateHash(rt.app)
    rt.store.close()
    let f = open(path, fmAppend)
    f.write "{\"seq\":99,\"at\":1,\"kind\":\"Sai"
    f.close
    let again = replay[DeskApp](openFileStore(path))
    again.store.close()
    check again.seq == 16
    check stateHash(again.app) == live

  test "appending after a half-written last line keeps the log replayable":
    let path = work / "desk.jsonl"
    var rt = Runtime[DeskApp](store: openFileStore(path))
    script(rt)
    rt.store.close()
    let f = open(path, fmAppend)
    f.write "{\"seq\":99,\"at\":1,\"kind\":\"Sai"
    f.close
    var next = replay[DeskApp](openFileStore(path))
    next.clock = proc (): int64 = 1_800_000_000_000'i64
    discard next.execute("SendMessage", %*{"game": "fox", "text": "add a fox"})
    check next.seq > 16
    let live = stateHash(next.app)
    let total = next.seq
    next.store.close()
    let again = replay[DeskApp](openFileStore(path))
    again.store.close()
    check again.seq == total
    check stateHash(again.app) == live
