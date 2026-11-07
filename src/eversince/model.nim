## The model file: parser and checker. Plain procs, so the same code runs inside the compiler
## (`sealModel`) and at run time (a command-line tool), and the two cannot disagree.

import std/[strutils, sequtils, algorithm]

type
  Block* = object
    kind*, name*: string
    fields*: seq[string]                              ## "name:type"
    edges*: seq[tuple[key: string, vals: seq[string]]] ## reads, produces, refuses, consumes, ...
  Slice* = object
    name*: string
    steps*: seq[string]
  Model* = object
    blocks*: seq[Block]
    slices*: seq[Slice]

const
  codeKinds* = ["record", "event", "command", "view", "query", "processor"]
  edgeOrder = ["reads", "consumes", "produces", "refuses", "issues", "returns", "queries", "commands"]

proc edge*(b: Block, key: string): seq[string] =
  for e in b.edges:
    if e.key == key: return e.vals

proc canonical*(b: Block): string =
  ## One block as one line: fields in declared order, edges in a fixed order, values sorted.
  result = b.kind & " " & b.name
  for f in b.fields: result.add " " & f
  for key in edgeOrder:
    let vals = b.edge(key)
    if vals.len > 0: result.add " | " & key & " " & vals.sorted.join(",")

proc parseModel*(text: string): Model =
  for raw in text.splitLines:
    let line = raw.split('#')[0].strip
    if line.len == 0: continue
    if line.startsWith("slice "):
      let parts = line[6 .. ^1].split(':', 1)
      doAssert parts.len == 2, "slice line needs `name: A -> B`: " & line
      result.slices.add Slice(name: parts[0].strip, steps: parts[1].split("->").mapIt(it.strip))
      continue
    let segs = line.split('|').mapIt(it.strip)
    let head = segs[0].splitWhitespace
    doAssert head.len >= 2, "model line needs a kind and a name: " & line
    var b = Block(kind: head[0], name: head[1], fields: head[2 .. ^1])
    for seg in segs[1 .. ^1]:
      let kv = seg.splitWhitespace(maxsplit = 1)
      doAssert kv.len == 2, "edge needs a key and values: " & line
      b.edges.add (kv[0], kv[1].split(',').mapIt(it.strip))
    result.blocks.add b

proc find*(m: Model, name: string): Block =
  for b in m.blocks:
    if b.name == name: return b

proc checkModel*(m: Model, code: seq[string]): tuple[errors, warnings: seq[string]] =
  ## `code` is the registry: one canonical line per block declared in code.
  let fromFile = m.blocks.filterIt(it.kind in codeKinds).mapIt(it.canonical)
  proc nameOf(line: string): string = line.splitWhitespace[0 .. 1].join(" ")
  for line in fromFile:
    if line in code: continue
    let twin = code.filterIt(it.nameOf == line.nameOf)
    if twin.len > 0:
      result.errors.add "model and code disagree about `" & line.nameOf & "`:\n    model: " & line & "\n    code:  " & twin[0]
    else:
      result.errors.add "the model declares a block the code lacks (write it, or delete the line):\n    " & line
  for line in code:
    if line notin fromFile and fromFile.filterIt(it.nameOf == line.nameOf).len == 0:
      result.errors.add "the code declares a block the model lacks (add this line to the model):\n    " & line
  # screens and slices live only in the model: every name they use must exist, every step must be a real edge
  proc has(name: string): bool = m.blocks.anyIt(it.name == name)
  for b in m.blocks:
    if b.kind == "screen":
      for n in b.edge("queries") & b.edge("commands"):
        if not has(n): result.errors.add "screen " & b.name & " names `" & n & "`, which does not exist"
  for s in m.slices:
    for i in 0 ..< s.steps.len - 1:
      let a = m.find(s.steps[i])
      let b = m.find(s.steps[i + 1])
      if a.name.len == 0 or b.name.len == 0:
        result.errors.add "slice \"" & s.name & "\": `" & (if a.name.len == 0: s.steps[i] else: s.steps[i + 1]) & "` does not exist"
        continue
      let step = a.kind & "->" & b.kind
      let ok = case step
        of "screen->command": b.name in a.edge("commands")
        of "processor->command": b.name in a.edge("issues")
        of "command->event": b.name in a.edge("produces")
        of "event->view", "event->processor": a.name in b.edge("consumes")
        of "view->query", "view->command": a.name in b.edge("reads")
        of "query->screen": a.name in b.edge("queries")
        else:
          result.errors.add "slice \"" & s.name & "\": a " & a.kind & " cannot lead to a " & b.kind & " (" & a.name & " -> " & b.name & ")"
          continue
      if not ok:
        result.errors.add "slice \"" & s.name & "\": " & a.name & " -> " & b.name & " is not an edge the blocks declare"
  # lints: things that exist but connect to nothing
  proc usedIn(name: string, kinds: openArray[string], keys: openArray[string]): bool =
    for b in m.blocks:
      if b.kind in kinds:
        for k in keys:
          if name in b.edge(k): return true
  for b in m.blocks:
    case b.kind
    of "event":
      if not usedIn(b.name, ["command"], ["produces"]): result.warnings.add "event " & b.name & " is produced by no command"
      if not usedIn(b.name, ["view", "processor"], ["consumes"]): result.warnings.add "event " & b.name & " is consumed by no view or processor"
    of "view":
      if not usedIn(b.name, ["query", "command"], ["reads"]): result.warnings.add "view " & b.name & " is read by no query or command"
    of "command":
      if not usedIn(b.name, ["screen"], ["commands"]) and not usedIn(b.name, ["processor"], ["issues"]):
        result.warnings.add "command " & b.name & " is on no screen and issued by no processor"
    of "query":
      if not usedIn(b.name, ["screen"], ["queries"]): result.warnings.add "query " & b.name & " is on no screen"
    else: discard

proc counts*(m: Model): string =
  var parts: seq[string]
  for k in ["command", "event", "view", "query", "processor", "screen"]:
    parts.add $m.blocks.countIt(it.kind == k) & " " & k & (if k == "query": "/queries" else: "s")
  parts.join(", ") & ", " & $m.slices.len & " slices"
