## The model file: parser and checker. Plain procs, so the same code runs inside the compiler
## (`sealModel`) and at run time (a command-line tool), and the two cannot disagree.

import std/[strutils, sequtils, algorithm, tables]

type
  ModelParseError* = object of ValueError  ## a line of the model file is not a block or a slice
  Block* = object
    kind*, name*: string
    line*: int                                        ## 1-based line in the model file, 0 when not parsed from one
    fields*: seq[string]                              ## "name:type"
    edges*: seq[tuple[key: string, vals: seq[string]]] ## reads, produces, refuses, consumes, ...
  Slice* = object
    name*: string
    line*: int
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

proc atLine(file: string, line: int): string =
  ## `desk.em:21`, or `line 21` when the file's name is not known.
  if file.len > 0: file & ":" & $line else: "line " & $line

proc parseModel*(text: string, file = ""): Model =
  ## `file` is only used to word a parse error: `desk.em:5: ...`.
  var lineNo = 0
  for raw in text.splitLines:
    inc lineNo
    let line = raw.split('#')[0].strip
    if line.len == 0: continue
    proc bad(why: string) {.noreturn.} =
      raise newException(ModelParseError, atLine(file, lineNo) & ": " & why & "\n    " & line)
    if line.startsWith("slice "):
      let parts = line[6 .. ^1].split(':', 1)
      if parts.len != 2: bad "slice line needs `slice title : A -> B`; add the `:` after the title"
      result.slices.add Slice(name: parts[0].strip, steps: parts[1].split("->").mapIt(it.strip), line: lineNo)
      continue
    let segs = line.split('|').mapIt(it.strip)
    let head = segs[0].splitWhitespace
    if head.len < 2: bad "model line needs a kind and a name, like `event Name field:type`"
    var b = Block(kind: head[0], name: head[1], fields: head[2 .. ^1], line: lineNo)
    for seg in segs[1 .. ^1]:
      let kv = seg.splitWhitespace(maxsplit = 1)
      if kv.len != 2: bad "edge needs a key and values, like `| reads View,Other`; remove the `|` or finish the edge"
      b.edges.add (kv[0], kv[1].split(',').mapIt(it.strip))
    result.blocks.add b

proc find*(m: Model, name: string): Block =
  for b in m.blocks:
    if b.name == name: return b

proc stepHint(a, b: Block): string =
  ## What to write so that the step a -> b becomes an edge the blocks declare.
  case a.kind & "->" & b.kind
  of "screen->command": "add `" & b.name & "` to the `commands` of screen " & a.name
  of "processor->command": "add `" & b.name & "` to the `issues` of processor " & a.name
  of "command->event": "add `" & b.name & "` to the `produces` of command " & a.name
  of "event->view", "event->processor": "give " & b.kind & " " & b.name & " an `on " & a.name & ":` handler"
  of "view->query", "view->command": "add `" & a.name & "` to the `reads` of " & b.kind & " " & b.name
  of "query->screen": "add `" & a.name & "` to the `queries` of screen " & b.name
  else: ""

proc checkModel*(m: Model, code: seq[string], file = "",
                 codeAt = initTable[string, string]()): tuple[errors, warnings: seq[string]] =
  ## `code` is the registry: one canonical line per block declared in code. `file` names the model
  ## file in messages; `codeAt` maps a block name to where the code declares it (`desk.nim:114`).
  ## Every message starts with the line to look at, and says what to do about it.
  proc at(line: int): string = (if line > 0: atLine(file, line) & ": " else: "")
  proc inCode(name: string): string = (if name in codeAt: codeAt[name] & ": " else: "")
  let fromFile = m.blocks.filterIt(it.kind in codeKinds)
  proc nameOf(line: string): string = line.splitWhitespace[0 .. 1].join(" ")
  for b in fromFile:
    let line = b.canonical
    if line in code: continue
    let twin = code.filterIt(it.nameOf == line.nameOf)
    if twin.len > 0:
      result.errors.add at(b.line) & "model and code disagree about `" & line.nameOf & "`" &
        (if b.name in codeAt: " (code: " & codeAt[b.name] & ")" else: "") &
        "; edit the model line or the code until they match:\n    model: " & line & "\n    code:  " & twin[0]
    else:
      result.errors.add at(b.line) & "the model declares a block the code lacks (write it, or delete the line):\n    " & line
  let modelLines = fromFile.mapIt(it.canonical)
  for line in code:
    if line notin modelLines and fromFile.filterIt(it.canonical.nameOf == line.nameOf).len == 0:
      result.errors.add inCode(line.splitWhitespace[1]) & "the code declares a block the model lacks (add this line to the model):\n    " & line
  # screens and slices live only in the model: every name they use must exist, every step must be a real edge
  proc has(name: string): bool = m.blocks.anyIt(it.name == name)
  for b in m.blocks:
    if b.kind == "screen":
      for n in b.edge("queries") & b.edge("commands"):
        if not has(n): result.errors.add at(b.line) & "screen " & b.name & " names `" & n & "`, which does not exist (fix the name, or declare the block)"
  for s in m.slices:
    var missing: seq[string]
    for i in 0 ..< s.steps.len - 1:
      let a = m.find(s.steps[i])
      let b = m.find(s.steps[i + 1])
      if a.name.len == 0 or b.name.len == 0:
        let gone = if a.name.len == 0: s.steps[i] else: s.steps[i + 1]
        if gone notin missing:
          missing.add gone
          result.errors.add at(s.line) & "slice \"" & s.name & "\": `" & gone & "` does not exist (fix the name in the slice, or declare the block)"
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
          result.errors.add at(s.line) & "slice \"" & s.name & "\": a " & a.kind & " cannot lead to " & (if b.kind[0] in "aeiou": "an " else: "a ") & b.kind &
            " (" & a.name & " -> " & b.name & "); a step goes screen->command, command->event, event->view or processor, view->query or command, query->screen, processor->command"
          continue
      if not ok:
        result.errors.add at(s.line) & "slice \"" & s.name & "\": " & a.name & " -> " & b.name & " is not an edge the blocks declare (" & stepHint(a, b) & ", or fix the slice)"
  # lints: things that exist but connect to nothing
  proc usedIn(name: string, kinds: openArray[string], keys: openArray[string]): bool =
    for b in m.blocks:
      if b.kind in kinds:
        for k in keys:
          if name in b.edge(k): return true
  for b in m.blocks:
    case b.kind
    of "event":
      if not usedIn(b.name, ["command"], ["produces"]):
        result.warnings.add at(b.line) & "event " & b.name & " is produced by no command (add it to a command's `produces`, or delete it)"
      if not usedIn(b.name, ["view", "processor"], ["consumes"]):
        result.warnings.add at(b.line) & "event " & b.name & " is consumed by no view or processor (give one an `on " & b.name & ":` handler, or delete it)"
    of "view":
      if not usedIn(b.name, ["query", "command"], ["reads"]):
        result.warnings.add at(b.line) & "view " & b.name & " is read by no query or command (add it to a `reads` line, or delete it)"
    of "command":
      if not usedIn(b.name, ["screen"], ["commands"]) and not usedIn(b.name, ["processor"], ["issues"]):
        result.warnings.add at(b.line) & "command " & b.name & " is on no screen and issued by no processor (add it to a screen's `commands` in the model, or to a processor's `issues`)"
    of "query":
      if not usedIn(b.name, ["screen"], ["queries"]):
        result.warnings.add at(b.line) & "query " & b.name & " is on no screen (add it to a screen's `queries` in the model)"
    else: discard

proc counts*(m: Model): string =
  var parts: seq[string]
  for k in ["command", "event", "view", "query", "processor", "screen"]:
    parts.add $m.blocks.countIt(it.kind == k) & " " & k & (if k == "query": "/queries" else: "s")
  parts.join(", ") & ", " & $m.slices.len & " slices"
