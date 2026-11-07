## Five declaration macros (`event`, `command`, `view`, `query`, `processor`, plus `record` for
## plain value types) register every block in a compile-time registry. `sealModel` then
##   1. generates the one dispatcher per block kind (`apply`, `decide`, `answer`, `react`),
##   2. compares the registry with a hand-readable model file and stops the build on any difference.
## Macros only declare: nothing clever happens inside a body.

import std/[macros, macrocache, json, strutils, sequtils, os]
import ./[types, model]

const
  regLines = CacheSeq"eversince.lines"       ## one canonical model line per block
  regNames = CacheTable"eversince.names"     ## block name -> kind, to refuse a second block of one name
  regViews = CacheSeq"eversince.views"       ## view names
  regViewOn = CacheSeq"eversince.viewOn"     ## "View Event"
  regCommands = CacheSeq"eversince.commands" ## "Command View,View"
  regQueries = CacheSeq"eversince.queries"   ## "Query View,View"
  regProcOn = CacheSeq"eversince.procOn"     ## "Processor Event"


proc neutralType(n: NimNode): string {.compileTime.} =
  ## The type as the model file spells it, so a kit in another language can read the same line.
  n.repr.replace(" ", "").replace("seq[", "list[")

type FieldDef = tuple[name: string, typ: NimNode]

proc parseFields(body: NimNode): seq[FieldDef] {.compileTime.} =
  for st in body:
    if st.kind == nnkDiscardStmt: continue
    if st.kind != nnkCall or st.len != 2: error("expected `name: Type`", st)
    result.add ($st[0], st[1][0])

proc fieldsText(fields: seq[FieldDef]): seq[string] {.compileTime.} =
  fields.mapIt(it.name & ":" & neutralType(it.typ))

proc objectDef(name: string, fields: seq[FieldDef]): NimNode {.compileTime.} =
  var rec = newNimNode(nnkRecList)
  for f in fields: rec.add newIdentDefs(postfix(ident f.name, "*"), f.typ)
  newNimNode(nnkTypeSection).add(
    newNimNode(nnkTypeDef).add(postfix(ident name, "*"), newEmptyNode(),
      newNimNode(nnkObjectTy).add(newEmptyNode(), newEmptyNode(), rec)))

proc pure(): NimNode {.compileTime.} =
  ## `func` forbids globals, clocks, files and `echo`; `tags: []` also forbids what `func` lets
  ## through (reading the environment), and names the effect in the error.
  newNimNode(nnkPragma).add(newColonExpr(ident"tags", newNimNode(nnkBracket)))

proc names(st: NimNode): seq[string] {.compileTime.} =
  for i in 1 ..< st.len: result.add st[i].repr

proc register(b: Block) {.compileTime.} =
  if regNames.hasKey(b.name):
    error("`" & b.name & "` is declared twice; every block needs its own name")
  regNames[b.name] = newLit(b.kind)
  regLines.add newLit(b.canonical)

macro record*(name, body: untyped): untyped =
  ## A plain value type that events, commands and views may carry.
  let fields = parseFields(body)
  register Block(kind: "record", name: $name, fields: fieldsText(fields))
  objectDef($name, fields)

macro event*(name, body: untyped): untyped =
  ## An immutable fact. Its schema is the Nim object type this generates.
  let fields = parseFields(body)
  register Block(kind: "event", name: $name, fields: fieldsText(fields))
  objectDef($name, fields)

macro command*(name, body: untyped): untyped =
  ## A request to change state. `decide` becomes a `func`: it cannot read a clock, a file or a
  ## global, and it can only `emit` the events listed under `produces`.
  let n = $name
  var fields: seq[FieldDef]
  var reads, produces, refuses: seq[string]
  var decideBody: NimNode
  for st in body:
    if st.kind == nnkCall and $st[0] == "fields": fields = parseFields(st[1])
    elif st.kind == nnkCall and $st[0] == "decide": decideBody = st[1]
    elif st.kind == nnkCommand and $st[0] == "reads": reads = st.names
    elif st.kind == nnkCommand and $st[0] == "produces": produces = st.names
    elif st.kind == nnkCommand and $st[0] == "refuses": refuses = st.names
    else: error("command " & n & ": expected fields:, reads, produces, refuses or decide:", st)
  if decideBody.isNil: error("command " & n & " has no decide: section", name)
  register Block(kind: "command", name: n, fields: fieldsText(fields),
                 edges: @[("reads", reads), ("produces", produces), ("refuses", refuses)])
  regCommands.add newLit(n & " " & reads.join(","))
  result = newStmtList(objectDef(n, fields))
  var prelude = ""
  if refuses.len > 0:
    result.add parseStmt("type " & n & "Refusal* = enum " & refuses.join(", "))
    prelude.add "template refuse(refusal: " & n & "Refusal, msg: string) {.used.} =\n" &
                "  return Decision(refused: true, code: $refusal, message: msg)\n"
  for p in produces:
    prelude.add "template emit(e: " & p & ") {.used.} = result.events.add envelopeOf(\"" & p & "\", e)\n"
  prelude.add "template emit[T](e: T) {.used.} =\n  {.error: \"command " & n & " emits \" & $T & \", which its `produces` line does not list\".}\n"
  var params = @[ident"Decision", newIdentDefs(ident"cmd", ident n)]
  for r in reads: params.add newIdentDefs(ident lowerFirst(r), ident r)
  params.add newIdentDefs(ident"ctx", ident"Ctx")
  result.add newProc(postfix(ident"decide", "*"), params,
                     newStmtList(parseStmt(prelude), decideBody), nnkFuncDef, pure())

macro view*(name, body: untyped): untyped =
  ## A fold over events. Each `on Event:` becomes a `func`, so a view cannot do I/O either.
  let n = $name
  var fields: seq[FieldDef]
  var consumes: seq[string]
  result = newStmtList()
  var folds = newStmtList()
  for st in body:
    if st.kind == nnkCall and $st[0] == "state": fields = parseFields(st[1])
    elif st.kind == nnkCommand and $st[0] == "on" and st.len == 3:
      let ev = st[1].repr
      if ev in consumes: error("view " & n & " handles " & ev & " twice", st)
      consumes.add ev
      regViewOn.add newLit(n & " " & ev)
      folds.add newProc(postfix(ident"evolve", "*"),
        [newEmptyNode(), newIdentDefs(ident"state", newNimNode(nnkVarTy).add(ident n)),
         newIdentDefs(ident"e", st[1])], st[2], nnkFuncDef, pure())
    else: error("view " & n & ": expected state: or `on Event:`", st)
  register Block(kind: "view", name: n, fields: fieldsText(fields), edges: @[("consumes", consumes)])
  regViews.add newLit(n)
  result.add objectDef(n, fields)
  result.add folds

macro query*(name, body: untyped): untyped =
  ## Reads views, returns data, changes nothing: views arrive as immutable parameters of a `func`.
  let n = $name
  var fields: seq[FieldDef]
  var reads: seq[string]
  var returns, answerBody: NimNode
  for st in body:
    if st.kind == nnkCall and $st[0] == "fields": fields = parseFields(st[1])
    elif st.kind == nnkCall and $st[0] == "answer": answerBody = st[1]
    elif st.kind == nnkCommand and $st[0] == "reads": reads = st.names
    elif st.kind == nnkCommand and $st[0] == "returns": returns = st[1]
    else: error("query " & n & ": expected fields:, reads, returns or answer:", st)
  if answerBody.isNil or returns.isNil: error("query " & n & " needs returns and answer:", name)
  register Block(kind: "query", name: n, fields: fieldsText(fields),
                 edges: @[("reads", reads), ("returns", @[neutralType(returns)])])
  regQueries.add newLit(n & " " & reads.join(","))
  var params = @[returns, newIdentDefs(ident"q", ident n)]
  for r in reads: params.add newIdentDefs(ident lowerFirst(r), ident r)
  result = newStmtList(objectDef(n, fields),
                       newProc(postfix(ident"answer", "*"), params, answerBody, nnkFuncDef, pure()))

macro processor*(name, body: untyped): untyped =
  ## Reacts to events with side effects (the only block that may have any), and may only `issue`
  ## the commands listed under `issues`.
  let n = $name
  var issues, consumes: seq[string]
  var ons: seq[NimNode]
  for st in body:
    if st.kind == nnkCommand and $st[0] == "issues": issues = st.names
    elif st.kind == nnkCommand and $st[0] == "on" and st.len == 3: ons.add st
    else: error("processor " & n & ": expected issues or `on Event:`", st)
  result = newStmtList(parseStmt("type " & n & "* = object"))
  var prelude = ""
  for c in issues:
    prelude.add "template issue(c: " & c & ") {.used.} = issueCb(\"" & c & "\", %c)\n"
  prelude.add "template issue[T](c: T) {.used.} =\n  {.error: \"processor " & n & " issues \" & $T & \", which its `issues` line does not list\".}\n"
  for st in ons:
    consumes.add st[1].repr
    regProcOn.add newLit(n & " " & st[1].repr)
    result.add newProc(postfix(ident"react", "*"),
      [newEmptyNode(), newIdentDefs(ident"p", newNimNode(nnkBracketExpr).add(ident"typedesc", ident n)),
       newIdentDefs(ident"e", st[1]), newIdentDefs(ident"issueCb", ident"IssueProc")],
      newStmtList(parseStmt(prelude), st[2]))
  register Block(kind: "processor", name: n, edges: @[("consumes", consumes), ("issues", issues)])

macro sealModel*(appName: untyped, modelFile: static string): untyped =
  ## Call once, after every block is declared. Generates the app type and the four dispatchers,
  ## and stops the build when the model file and the code disagree.
  let app = $appName
  let code = toSeq(regLines).mapIt(it.strVal)
  # 1. the model check
  if defined(eversinceWrite) or not fileExists(modelFile):
    var kept: seq[string]
    if fileExists(modelFile):
      for line in readFile(modelFile).splitLines:
        let first = line.strip.split(' ')[0]
        if first in ["screen", "slice"]: kept.add line
    writeFile(modelFile, "# Event model. Blocks are checked against the code by the compiler.\n" &
      code.join("\n") & "\n" & (if kept.len > 0: kept.join("\n") & "\n" else: ""))
    hint("eversince: wrote " & modelFile)
  let model = parseModel(readFile(modelFile))
  let (errors, warnings) = checkModel(model, code)
  for w in warnings:
    if defined(eversinceStrict): error("event model (strict): " & w) else: warning("event model: " & w)
  if errors.len > 0:
    error("event model " & modelFile.extractFilename & " does not match the code\n  " & errors.join("\n  "))
  # 2. the dispatchers: one per block kind, the same for every app
  let views = toSeq(regViews).mapIt(it.strVal)
  var src = "type " & app & "* = object\n"
  for v in views: src.add "  " & lowerFirst(v) & "*: " & v & "\n"
  proc byEvent(reg: CacheSeq): seq[tuple[ev: string, owners: seq[string]]] =
    for row in reg:
      let p = row.strVal.split(' ')
      var found = false
      for item in result.mitems:
        if item.ev == p[1]:
          item.owners.add p[0]
          found = true
      if not found: result.add (p[1], @[p[0]])
  src.add "proc apply*(app: var " & app & ", env: Envelope) =\n  case env.kind\n"
  for (ev, owners) in byEvent(regViewOn):
    src.add "  of \"" & ev & "\":\n    let e = env.data.to(" & ev & ")\n"
    for v in owners: src.add "    evolve(app." & lowerFirst(v) & ", e)\n"
  src.add "  else: discard\n"
  src.add "proc react*(app: " & app & ", env: Envelope, issueCb: IssueProc) =\n  case env.kind\n"
  for (ev, owners) in byEvent(regProcOn):
    src.add "  of \"" & ev & "\":\n    let e = env.data.to(" & ev & ")\n"
    for p in owners: src.add "    react(" & p & ", e, issueCb)\n"
  src.add "  else: discard\n"
  proc viewArgs(row: string): string =
    let p = row.split(' ')
    if p.len > 1 and p[1].len > 0:
      for v in p[1].split(','): result.add ", app." & lowerFirst(v)
  src.add "proc decide*(app: " & app & ", name: string, data: JsonNode, ctx: Ctx): Decision =\n  case name\n"
  for row in regCommands:
    let c = row.strVal.split(' ')[0]
    src.add "  of \"" & c & "\": decide(data.to(" & c & ")" & viewArgs(row.strVal) & ", ctx)\n"
  src.add "  else: Decision(refused: true, code: \"unknownCommand\", message: name)\n"
  src.add "proc answer*(app: " & app & ", name: string, data: JsonNode): JsonNode =\n  case name\n"
  for row in regQueries:
    let q = row.strVal.split(' ')[0]
    src.add "  of \"" & q & "\": %answer(data.to(" & q & ")" & viewArgs(row.strVal) & ")\n"
  src.add "  else: newJNull()\n"
  src.add "const " & lowerFirst(app) & "Catalog* = " & code.join("\n").escape & "\n"
  result = if defined(eversinceNoDispatch): newStmtList() else: parseStmt(src)
