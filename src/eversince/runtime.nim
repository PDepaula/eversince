## The runtime: the one way a command is handled, replay, and the scenario runner.

import std/[json, sequtils]
import ./[types, store, positions]

type Runtime*[A] = object
  app*: A
  store*: Store
  positions*: Positions ## where each processor has got to; nil is a fresh `MemPositions`, made when first needed
  seq*: int64
  clock*: proc (): int64 ## the shell's clock; a test or a replay hands in a fixed one
  pending: seq[Envelope] ## events some processor has not been given, and checkpointed, yet
  delivering: bool

proc lowest[A](rt: Runtime[A], names: seq[string]): int64 =
  ## The smallest position of any processor, and never past the head of the log.
  result = rt.seq
  for n in names: result = min(result, rt.positions.get(n))

proc catchUp*[A](rt: var Runtime[A])

proc execute*[A](rt: var Runtime[A], name: string, data: JsonNode): Decision =
  ## decide (pure) -> stamp -> append -> fold into the views -> let processors catch up.
  mixin decide, apply
  let ctx = Ctx(now: rt.clock(), nextSeq: rt.seq + 1)
  result = decide(rt.app, name, data, ctx)
  if result.refused: return
  for i in 0 ..< result.events.len:
    result.events[i].seq = rt.seq + 1 + i
    result.events[i].at = ctx.now
  rt.store.append(result.events)
  rt.seq += result.events.len
  for e in result.events:
    apply(rt.app, e)
    rt.pending.add e
  rt.catchUp()

proc catchUp*[A](rt: var Runtime[A]) =
  ## Give every processor each event after its position, in log order. The commands they issue are
  ## handled when a round is done, and only then is the processors' position moved on: a crash in
  ## between gives them the same events again, so a processor, and the commands it issues, must be
  ## safe to repeat (spec 06). A processor that fails stays where it was, and the error goes up.
  ## Called by `execute`; call it once after `replay` to deliver what was missed before a restart.
  mixin processors, deliver
  if rt.delivering: return
  rt.delivering = true
  defer: rt.delivering = false
  if rt.positions.isNil: rt.positions = MemPositions()
  let names = processors(rt.app)
  while true:
    let head = rt.seq
    var at: seq[int64]
    for n in names: at.add rt.positions.get(n)
    var low = head
    for p in at: low = min(low, p)
    var queue: seq[(string, JsonNode)]
    let cb = proc (n: string, d: JsonNode) = queue.add (n, d)
    for e in rt.pending:
      if e.seq <= low or e.seq > head: continue
      for i, n in names:
        if e.seq > at[i]: deliver(rt.app, n, e, cb)
    for (n, d) in queue: discard rt.execute(n, d)
    var moved: seq[(string, int64)]
    for n in names:
      if rt.positions.get(n) != head: moved.add (n, head)
    if moved.len > 0: rt.positions.save moved
    rt.pending = rt.pending.filterIt(it.seq > head)
    if rt.seq == head: break

proc redeliver*[A](rt: var Runtime[A], processor: string, e: Envelope) =
  ## Give one event to one processor again, whatever its position, and handle the commands it
  ## issues. The position does not move. This is what a restart does behind the scenes.
  mixin deliver
  var queue: seq[(string, JsonNode)]
  deliver(rt.app, processor, e, proc (n: string, d: JsonNode) = queue.add (n, d))
  for (n, d) in queue: discard rt.execute(n, d)

proc replay*[A](store: Store, positions: Positions = nil): Runtime[A] =
  ## The views are a fold of the log: no decision runs again, no processor fires. The processors'
  ## positions are those in `positions`, none for a processor not in it; `catchUp` then gives them
  ## what they missed. With no `positions` the caller keeps none, and every processor counts as
  ## having been given the whole log.
  mixin apply, processors
  result.store = store
  let events = store.load
  for e in events:
    apply(result.app, e)
    result.seq = e.seq
  let names = processors(result.app)
  if positions.isNil:
    result.positions = MemPositions()
    result.positions.save names.mapIt((it, result.seq))
  else:
    result.positions = positions
    var past: seq[(string, int64)]   ## a position past the head means the log was deleted and began again: start over from its head
    for n in names:
      if positions.get(n) > result.seq: past.add (n, result.seq)
    if past.len > 0: positions.save past
    let low = result.lowest(names)
    result.pending = events.filterIt(it.seq > low)

proc runScenario*[A](sc: JsonNode): string =
  ## A language-neutral scenario: given events, when a command, then events or a refusal (and,
  ## optionally, what a view then holds). "" when it passes, else why not.
  mixin apply, decide
  var app: A
  var seq = 0'i64
  for g in sc{"given"}.getElems:
    inc seq
    apply(app, Envelope(seq: seq, kind: g["kind"].getStr, data: g["data"]))
  let then = sc["then"]
  if sc.hasKey("when"):
    let d = decide(app, sc["when"]["command"].getStr, sc["when"]["data"], Ctx(now: sc{"now"}.getBiggestInt, nextSeq: seq + 1))
    if then.hasKey("refused"):
      if not d.refused: return "expected refusal " & then["refused"].getStr & ", got " & $d.events.len & " event(s)"
      if d.code != then["refused"].getStr: return "expected refusal " & then["refused"].getStr & ", got " & d.code
    else:
      if d.refused: return "refused with " & d.code & ": " & d.message
      let got = %d.events.mapIt(%*{"kind": it.kind, "data": it.data})
      if then.hasKey("events") and got != then["events"]: return "events differ: got " & $got
      for e in d.events: apply(app, e)
  if then.hasKey("view"):
    let all = %app
    for name, want in then["view"]:
      let got = all{lowerFirst(name)}
      for key, val in want:
        if got{key}.isNil: return "view " & name & " has no field " & key
        if got{key} != val: return "view " & name & "." & key & " is " & $got{key} & ", expected " & $val
