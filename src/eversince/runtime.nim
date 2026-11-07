## The runtime: the one way a command is handled, replay, and the scenario runner.

import std/[json, sequtils]
import ./[types, store]

type Runtime*[A] = object
  app*: A
  store*: Store
  seq*: int64
  clock*: proc (): int64 ## the shell's clock; a test or a replay hands in a fixed one

proc execute*[A](rt: var Runtime[A], name: string, data: JsonNode): Decision =
  ## decide (pure) -> stamp -> append -> fold into the views -> let processors react.
  mixin decide, apply, react
  let ctx = Ctx(now: rt.clock(), nextSeq: rt.seq + 1)
  result = decide(rt.app, name, data, ctx)
  if result.refused: return
  for i in 0 ..< result.events.len:
    result.events[i].seq = rt.seq + 1 + i
    result.events[i].at = ctx.now
  rt.store.append(result.events)
  rt.seq += result.events.len
  for e in result.events: apply(rt.app, e)
  var queue: seq[(string, JsonNode)]
  let cb = proc (n: string, d: JsonNode) = queue.add (n, d)
  for e in result.events: react(rt.app, e, cb)
  for (n, d) in queue: discard rt.execute(n, d)

proc replay*[A](store: Store): Runtime[A] =
  ## The state is a fold of the log: no decision runs again, no processor fires.
  mixin apply
  result.store = store
  for e in store.load:
    apply(result.app, e)
    result.seq = e.seq

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
