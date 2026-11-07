## The SQLite store replays to the same state as the memory store. Needs the system's SQLite
## library, so it is not part of the Windows run.
import std/[unittest, os, hashes, strutils]
import eversince, eversince/store_sqlite
import ../examples/desk/desk

let work = getTempDir() / "eversince-tsqlite"

proc stateHash(app: DeskApp): string = toHex(hash($(%app)).int, 16)

proc script(rt: var Runtime[DeskApp]) =
  var tick = 1_700_000_000_000'i64
  rt.clock = proc (): int64 = tick
  runAgent = proc (game, text: string): seq[string] = @["On it."]
  for (name, data) in [
      ("SendMessage", %*{"game": "cat", "text": "make the cat jump higher"}),
      ("SendMessage", %*{"game": "dog", "text": "add a bark"}),
      ("StopTurn", %*{"game": "cat"})]:
    tick += 1000
    discard rt.execute(name, data)

suite "sqlite store":
  test "events survive a reopen and replay to the same state":
    removeDir(work)
    createDir(work)
    var mem = Runtime[DeskApp](store: MemStore())
    script(mem)
    let path = work / "desk.db"
    var rt = Runtime[DeskApp](store: openSqliteStore(path))
    script(rt)
    rt.store.close()
    let again = replay[DeskApp](openSqliteStore(path))
    check again.seq == mem.seq
    check stateHash(again.app) == stateHash(mem.app)
    again.store.close()
    removeDir(work)

  test "a second writer for a position already taken is refused":
    removeDir(work)
    createDir(work)
    let path = work / "dup.db"
    let s = openSqliteStore(path)
    let ev = Envelope(seq: 1, at: 1, kind: "MessageSent", data: %*{"game": "cat", "text": "a"})
    s.append([ev])
    expect IOError:
      s.append([ev])
    check s.load.len == 1
    s.close()
    removeDir(work)
