## Runs the prototype's evidence: catalogue, scenarios, replay across three stores, and timings.
##
##   nim c -r -d:release examples/desk/demo.nim [turns]
##
## The SQLite store needs the system's SQLite library; build with -d:eversinceNoSqlite to leave it
## out (the SQLite rows are then skipped).
import std/[os, strutils, times, monotimes]
import eversince, eversince/store_file
import desk
when not defined(eversinceNoSqlite):
  import eversince/store_sqlite

let here = currentSourcePath().parentDir
let work = getTempDir() / "eversince-desk-demo"

const storeKinds = when defined(eversinceNoSqlite): @["memory", "jsonl"] else: @["memory", "jsonl", "sqlite"]
const benchKinds = when defined(eversinceNoSqlite): @["memory", "jsonl", "jsonl+fsync"]
                   else: @["memory", "jsonl", "sqlite", "jsonl+fsync", "sqlite+full"]

proc openSql(path: string, sync = false): Store =
  when defined(eversinceNoSqlite): raise newException(IOError, "built without SQLite")
  else: openSqliteStore(path, sync)

proc stateHash(app: DeskApp): string = stateDigest(app)

proc section(title: string) = echo "\n== " & title

# 1. the catalogue an agent or a human reads
section "catalogue (from the compile-time registry)"
let model = parseModel(readFile(here / "desk.em"))
echo deskAppCatalog
echo "size: " & model.counts

# 2. the language-neutral scenarios
section "scenarios (scenarios.jsonl)"
var passed, failed = 0
for line in lines(here / "scenarios.jsonl"):
  if line.strip.len == 0: continue
  let sc = parseJson(line)
  let why = runScenario[DeskApp](sc)
  if why.len == 0: inc passed
  else:
    inc failed
    echo "FAIL " & sc["name"].getStr & ": " & why
echo $passed & " passed, " & $failed & " failed"

# 3. one script of commands, three stores, one state
section "replay across stores"
removeDir(work)
createDir(work)

proc script(rt: var Runtime[DeskApp]): tuple[accepted, refused: int] =
  var tick = 1_700_000_000_000'i64
  rt.clock = proc (): int64 = tick
  runAgent = proc (game, text: string): seq[string] = @["On it.", "Done: the cat jumps higher."]
  runStep = proc (game, kind: string): int = (if kind == "check": 0 else: 1)
  let cmds = [
    ("SendMessage", %*{"game": "cat", "text": "make the cat jump higher"}),
    ("StartStep", %*{"game": "cat", "kind": "check", "message": ""}),
    ("StartStep", %*{"game": "cat", "kind": "save", "message": ""}),
    ("StartStep", %*{"game": "cat", "kind": "save", "message": "higher jump"}),
    ("PickAgent", %*{"game": "cat", "agent": "codex"}),
    ("PickAgent", %*{"game": "cat", "agent": "gemini"}),
    ("SendMessage", %*{"game": "cat", "text": "  "}),
    ("SendMessage", %*{"game": "dog", "text": "add a bark"}),
    ("NewConversation", %*{"game": "dog"}),
    ("StopTurn", %*{"game": "cat"})]
  for (name, data) in cmds:
    tick += 1000
    if rt.execute(name, data).refused: inc result.refused else: inc result.accepted

var seen: seq[string]
for kind in storeKinds:
  let store: Store =
    if kind == "memory": MemStore()
    elif kind == "jsonl": openFileStore(work / "desk.jsonl")
    else: openSql(work / "desk.db")
  var rt = Runtime[DeskApp](store: store)
  let (acc, refd) = script(rt)
  let live = stateHash(rt.app)
  # reopen from disk where there is a disk, then fold the log again
  store.close()
  let again: Store =
    if kind == "memory": store
    elif kind == "jsonl": openFileStore(work / "desk.jsonl")
    else: openSql(work / "desk.db")
  let replayed = replay[DeskApp](again)
  echo kind.alignLeft(7) & " accepted=" & $acc & " refused=" & $refd & " events=" & $replayed.seq &
       " live=" & live & " replayed=" & stateHash(replayed.app)
  seen.add live
  seen.add stateHash(replayed.app)
  again.close()
var same = true
for h in seen:
  if h != seen[0]: same = false
echo "all " & $seen.len & " hashes equal: " & $same
echo "first lines of the jsonl log:"
for i, line in pairs(readFile(work / "desk.jsonl").splitLines):
  if i < 3: echo "  " & line

# a torn last line (a crash in the middle of a write) is skipped, not fatal
let torn = work / "torn.jsonl"
copyFile(work / "desk.jsonl", torn)
let f = open(torn, fmAppend)
f.write "{\"seq\":99,\"at\":1,\"kind\":\"Sai"
f.close
let tornStore = openFileStore(torn)
echo "torn tail: " & $replay[DeskApp](tornStore).seq & " events read, same state: " &
     $(stateHash(replay[DeskApp](tornStore).app) == seen[0])
tornStore.close()

# 4. timings
section "timings"
proc ms(a: MonoTime): string = formatFloat((getMonoTime() - a).inNanoseconds.float / 1e6, ffDecimal, 1) & " ms"

let turns = if paramCount() >= 1: parseInt(paramStr(1)) else: 20_000
runAgent = proc (game, text: string): seq[string] = @["ok"]
for kind in benchKinds:
  let durable = kind.contains("+")
  let n = if durable: min(turns, 500) else: turns # reaching the disk on every command is slow: a smaller run
  let path = work / ("bench-" & kind.replace("+", "-"))
  let store: Store =
    if kind == "memory": MemStore()
    elif kind.startsWith("jsonl"): openFileStore(path, sync = durable)
    else: openSql(path, sync = durable)
  var rt = Runtime[DeskApp](store: store)
  rt.clock = proc (): int64 = 1_700_000_000_000'i64
  var t = getMonoTime()
  for i in 0 ..< n:
    discard rt.execute("SendMessage", %*{"game": "cat", "text": "message " & $i})
  let events = rt.seq
  let writeT = ms(t)
  t = getMonoTime()
  let loaded = store.load
  let loadT = ms(t)
  t = getMonoTime()
  var app: DeskApp
  for e in loaded: apply(app, e)
  echo kind.alignLeft(12) & " " & $n & " turns, " & $(n * 3) & " commands -> " & $events & " events: execute " & writeT &
       ", load " & loadT & ", fold " & ms(t) & ", same state: " & $(stateHash(app) == stateHash(rt.app))
  store.close()
