## The store interface (`append`, `load`, `forget`, `close`), the memory store and the line form
## of an event. Durable stores live in `store_file` and `store_sqlite`.

import std/json
import ./types

const forgottenKind* = "eversince.forgotten"
  ## The kind of the placeholder a store leaves where forgetting removed the log's last events
  ## (`spec/14-forgetting.md`). Not an identifier, so no app event can have it.

type
  StreamOf* = proc (e: Envelope): string {.closure.}
    ## Names the stream an event belongs to ("" for none). A stream is what can be forgotten whole.
  Store* = ref object of RootObj
  MemStore* = ref object of Store
    log: seq[Envelope]
    streamOf*: StreamOf ## needed by `forget`

proc streamOfEvent*(streamOf: StreamOf, e: Envelope): string =
  ## "" for a store with no streams and for the placeholder, which belongs to none.
  if streamOf.isNil or e.kind == forgottenKind: "" else: streamOf(e)

proc withoutDropped*(log: seq[Envelope], keep: seq[bool]): seq[Envelope] =
  ## The events of `log` whose flag in `keep` is set, in order. If that loses the log's last
  ## position, one placeholder event stands at that position, so that the next position handed out
  ## never goes back. A placeholder already in the log is dropped when it is no longer needed.
  doAssert keep.len == log.len
  for i, e in log:
    if keep[i] and e.kind != forgottenKind: result.add e
  if log.len > 0 and (result.len == 0 or result[^1].seq < log[^1].seq):
    result.add Envelope(seq: log[^1].seq, at: log[^1].at, kind: forgottenKind, data: newJObject())

method append*(s: Store, evs: openArray[Envelope]) {.base.} = discard
method load*(s: Store): seq[Envelope] {.base.} = discard
method forget*(s: Store, stream: string) {.base.} =
  ## Removes every event of `stream` from the store, for good. A store that cannot says so.
  raise newException(CatchableError, "this store cannot forget a stream")
method close*(s: Store) {.base.} = discard

method append*(s: MemStore, evs: openArray[Envelope]) = s.log.add evs
method load*(s: MemStore): seq[Envelope] = s.log
method forget*(s: MemStore, stream: string) =
  if s.streamOf.isNil: raise newException(CatchableError, "this store has no streams: set streamOf")
  if stream.len == 0: raise newException(ValueError, "forget: the empty string names no stream")
  var keep: seq[bool]
  for e in s.log: keep.add streamOfEvent(s.streamOf, e) != stream
  if false in keep: s.log = withoutDropped(s.log, keep)

proc toLine*(e: Envelope): string =
  result = "{\"seq\":" & $e.seq & ",\"at\":" & $e.at & ",\"kind\":" & escapeJson(e.kind) & ",\"data\":"
  result.add $e.data
  result.add "}"

proc fromLine*(line: string): Envelope =
  let n = parseJson(line)
  Envelope(seq: n["seq"].getBiggestInt, at: n["at"].getBiggestInt, kind: n["kind"].getStr, data: n["data"])
