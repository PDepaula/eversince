## The store interface (`append`, `load`, `close`), the memory store and the line form of an
## event. Durable stores live in `store_file` and `store_sqlite`.

import std/json
import ./types

type
  Store* = ref object of RootObj
  MemStore* = ref object of Store
    log: seq[Envelope]

method append*(s: Store, evs: openArray[Envelope]) {.base.} = discard
method load*(s: Store): seq[Envelope] {.base.} = discard
method close*(s: Store) {.base.} = discard

method append*(s: MemStore, evs: openArray[Envelope]) = s.log.add evs
method load*(s: MemStore): seq[Envelope] = s.log

proc toLine*(e: Envelope): string =
  result = "{\"seq\":" & $e.seq & ",\"at\":" & $e.at & ",\"kind\":" & escapeJson(e.kind) & ",\"data\":"
  result.add $e.data
  result.add "}"

proc fromLine*(line: string): Envelope =
  let n = parseJson(line)
  Envelope(seq: n["seq"].getBiggestInt, at: n["at"].getBiggestInt, kind: n["kind"].getStr, data: n["data"])
