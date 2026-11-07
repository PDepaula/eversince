## Processors with a remembered position: delivery at least once, repeat-safe commands, a restart
## from the memory store and from the file store, replay, rewind, and a log that was reset.
import std/[unittest, os, strutils, hashes]
import eversince
import ../examples/desk/desk

let work = getTempDir() / "eversince-tprocessors"

proc stateHash(app: DeskApp): string = toHex(hash($(%app)).int, 16)

type Flaky = ref object of Positions
  ## Remembers like `MemPositions`, but its next save fails: a crash after the commands, before the checkpoint.
  inner: MemPositions
  failNext: bool

method get(p: Flaky, processor: string): int64 = p.inner.get(processor)
method save(p: Flaky, updates: openArray[(string, int64)]) =
  if p.failNext:
    p.failNext = false
    raise newException(IOError, "crash before the checkpoint")
  p.inner.save updates

var agentRuns = 0
var agentDown = false

proc shell() =
  agentRuns = 0
  agentDown = false
  runAgent = proc (game, text: string): seq[string] =
    inc agentRuns
    if agentDown: raise newException(IOError, "the agent is not there")
    @["On it.", "Done."]
  runStep = proc (game, kind: string): int = (if kind == "check": 0 else: 1)

proc fresh[A](rt: var Runtime[A]) =
  var tick = 1_700_000_000_000'i64
  rt.clock = proc (): int64 = tick

proc send(rt: var Runtime[DeskApp], game: string) =
  discard rt.execute("SendMessage", %*{"game": game, "text": "go " & game})

proc reference(): string =
  ## The state of one run in which nothing goes wrong.
  shell()
  var rt = Runtime[DeskApp](store: MemStore())
  fresh rt
  rt.send "cat"
  rt.send "dog"
  stateHash(rt.app)

suite "processor positions":
  setup:
    removeDir(work)
    createDir(work)
    shell()
  teardown:
    removeDir(work)

  test "a processor's position follows the log head after each command":
    var rt = Runtime[DeskApp](store: MemStore(), positions: MemPositions())
    fresh rt
    rt.send "cat"
    check rt.seq == 5   # MessageSent, TurnStarted, Said, Said, TurnEnded
    check rt.positions.get("TurnRunner") == 5
    check rt.positions.get("StepRunner") == 5
    check agentRuns == 1

  test "a processor that failed is given the event again after a restart (memory store)":
    let store = MemStore()
    let positions = MemPositions()
    var rt = Runtime[DeskApp](store: store, positions: positions)
    fresh rt
    agentDown = true
    expect IOError: rt.send "cat"
    check rt.seq == 2                        # the message and the turn are in the log
    check positions.get("TurnRunner") == 0   # and the processor has not moved
    # restart: the views from the log, the positions as remembered
    agentDown = false
    var again = replay[DeskApp](store, positions)
    fresh again
    check again.app.desk.running.len == 1  # the turn is still open: nobody ended it
    again.catchUp()
    check again.seq == 5
    check again.app.desk.running.len == 0
    check positions.get("TurnRunner") == 5
    again.send "dog"
    check stateHash(again.app) == reference()

  test "a processor that failed is given the event again after a restart (file store)":
    let log = work / "desk.jsonl"
    let pos = work / "desk.positions"
    var rt = Runtime[DeskApp](store: openFileStore(log), positions: openFilePositions(pos))
    fresh rt
    agentDown = true
    expect IOError: rt.send "cat"
    rt.store.close()
    agentDown = false
    var again = replay[DeskApp](openFileStore(log), openFilePositions(pos))
    fresh again
    again.catchUp()
    again.send "dog"
    let live = stateHash(again.app)
    again.store.close()
    check live == reference()
    # and once more, from disk: the same views, and nothing left to deliver
    let third = replay[DeskApp](openFileStore(log), openFilePositions(pos))
    third.store.close()
    check stateHash(third.app) == live
    check readFile(pos) == "{\"StepRunner\":10,\"TurnRunner\":10}\n"
    check not fileExists(pos & ".tmp")

  test "a crash between the commands and the checkpoint repeats the delivery, not its effect":
    let store = MemStore()
    let positions = Flaky(inner: MemPositions())
    var rt = Runtime[DeskApp](store: store, positions: positions)
    fresh rt
    positions.failNext = true
    expect IOError: rt.send "cat"
    check rt.seq == 5                          # the processor's commands were applied
    check positions.get("TurnRunner") == 0     # and its position is still the start
    check agentRuns == 1
    var again = replay[DeskApp](store, positions)
    fresh again
    again.catchUp()
    check agentRuns == 2                       # given the event once more: at least once
    check again.seq == 5                       # the repeated commands were refused as stale
    check positions.get("TurnRunner") == 5
    again.send "dog"
    check stateHash(again.app) == reference()

  test "replay with no positions delivers nothing, as before":
    var rt = Runtime[DeskApp](store: MemStore())
    fresh rt
    rt.send "cat"
    let runs = agentRuns
    var again = replay[DeskApp](rt.store)
    fresh again
    again.catchUp()
    check agentRuns == runs
    check again.seq == 5

  test "a position past the head of the log is brought back to it":
    let positions = MemPositions()
    positions.save [("TurnRunner", 99'i64), ("StepRunner", 99'i64)]   # the log was deleted and began again
    var rt = replay[DeskApp](MemStore(), positions)
    fresh rt
    rt.send "cat"
    check rt.seq == 5
    check agentRuns == 1
    check positions.get("TurnRunner") == 5

  test "rewind gives a processor the log again from a position":
    var rt = Runtime[DeskApp](store: MemStore(), positions: MemPositions())
    fresh rt
    rt.send "cat"
    check agentRuns == 1
    rt.rewind("StepRunner")                    # it has no work in this log: nothing to see
    rt.catchUp()
    check agentRuns == 1
    rt.rewind("TurnRunner", 1)                 # from the second event: the turn start
    check rt.positions.get("TurnRunner") == 1
    rt.catchUp()
    check agentRuns == 2
    check rt.seq == 5                          # its commands were stale
    check rt.positions.get("TurnRunner") == 5

  test "an unreadable positions file raises instead of starting every processor over":
    let pos = work / "bad.positions"
    writeFile(pos, "{\"TurnRunner\":")
    expect IOError: discard openFilePositions(pos)
