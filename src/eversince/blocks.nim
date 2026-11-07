## Five declaration macros (`event`, `command`, `view`, `query`, `processor`, plus `record` for
## plain value types) register every block in a compile-time registry. `sealModel` then
##   1. generates the one dispatcher per block kind (`apply`, `decide`, `answer`, `react`),
##   2. compares the registry with a hand-readable model file and stops the build on any difference.
## Macros only declare: nothing clever happens inside a body.

import std/[macros, macrocache, json, strutils, sequtils, os, tables]
import ./[types, model]

const
  regLines = CacheSeq"eversince.lines"       ## one canonical model line per block
  regNames = CacheTable"eversince.names"     ## block name -> kind, to refuse a second block of one name
  regAt = CacheTable"eversince.at"           ## block name -> `file:line` of its declaration, for messages
  regViews = CacheSeq"eversince.views"       ## view names
  regViewOn = CacheSeq"eversince.viewOn"     ## "View Event"
  regCommands = CacheSeq"eversince.commands" ## "Command View,View"
  regQueries = CacheSeq"eversince.queries"   ## "Query View,View"
  regProcOn = CacheSeq"eversince.procOn"     ## "Processor Event"


proc where(n: NimNode): string {.compileTime.} =
  ## `desk.nim:114`: the user's own line, as the messages name it.
  let li = n.lineInfoObj
  li.filename.extractFilename & ":" & $li.line

proc relocate(n, info: NimNode): NimNode {.compileTime, discardable.} =
  ## Generated code carries the position of the generated text, which is no file at all. Give every
  ## node of it the position of `info`, a node of the user's own code, so that an error inside
  ## generated code is reported on the user's line. Never call it on the user's own nodes.
  n.copyLineInfo(info)
  for c in n: relocate(c, info)
  result = n

type DeclError = object of CatchableError
  ## A declaration that breaks a rule. Raised inside the kit, turned into a compile error on `at`.
  at: NimNode

proc bail(msg: string, at: NimNode) {.compileTime, noreturn.} =
  var e = newException(DeclError, msg)
  e.at = at
  raise e

proc failAt(msg: string, at: NimNode): NimNode {.compileTime.} =
  ## A compile error on `at`, without the compiler's stack trace through the kit's macros: the
  ## error is a pragma statement placed on the user's own line.
  relocate(newNimNode(nnkPragma).add(newColonExpr(ident"error", newLit(msg))), at)

template guard(body: untyped): NimNode =
  try: body
  except DeclError as e: failAt(e.msg, e.at)

proc neutralType(n: NimNode): string {.compileTime.} =
  ## The type as the model file spells it, so a kit in another language can read the same line.
  n.repr.replace(" ", "").replace("seq[", "list[")

type FieldDef = tuple[name: string, typ: NimNode, at: NimNode]   ## `at` is the field name as the user wrote it

proc parseFields(owner: string, body: NimNode): seq[FieldDef] {.compileTime.} =
  for st in body:
    if st.kind == nnkDiscardStmt: continue
    if st.kind != nnkCall or st.len != 2:
      bail(owner & ": expected `name: Type` for a field, found `" & st.repr & "`", st)
    result.add ($st[0], st[1][0], st[0])

proc fieldsText(fields: seq[FieldDef]): seq[string] {.compileTime.} =
  fields.mapIt(it.name & ":" & neutralType(it.typ))

proc objectDef(name: NimNode, fields: seq[FieldDef]): NimNode {.compileTime.} =
  ## The Nim type of a block. Its skeleton sits on the user's lines (the block's name, each field's
  ## name), so "type declared in ..." and a misspelt field point into the user's file.
  proc at(n, info: NimNode): NimNode = (n.copyLineInfo(info); n)
  var rec = newNimNode(nnkRecList).at(name)
  for f in fields:
    rec.add newIdentDefs(postfix(ident(f.name).at(f.at), "*").at(f.at), f.typ).at(f.at)
  newNimNode(nnkTypeSection).at(name).add(
    newNimNode(nnkTypeDef).at(name).add(postfix(ident($name).at(name), "*").at(name), newEmptyNode(),
      newNimNode(nnkObjectTy).at(name).add(newEmptyNode(), newEmptyNode(), rec)))

proc pure(): NimNode {.compileTime.} =
  ## `func` forbids globals, clocks, files and `echo`; `tags: []` also forbids what `func` lets
  ## through (reading the environment), and names the effect in the error.
  newNimNode(nnkPragma).add(newColonExpr(ident"tags", newNimNode(nnkBracket)))

proc names(st: NimNode): seq[string] {.compileTime.} =
  for i in 1 ..< st.len: result.add st[i].repr

proc nodes(st: NimNode): seq[NimNode] {.compileTime.} =
  ## The names after `reads`, `produces`, ... as the user wrote them, each on its own position.
  for i in 1 ..< st.len: result.add st[i]

proc register(b: Block, at: NimNode) {.compileTime.} =
  if regNames.hasKey(b.name):
    bail(b.kind & " " & b.name & ": `" & b.name & "` is declared twice (first declared at " & regAt[b.name].strVal &
         ", as `" & regNames[b.name].strVal & "`" & "); every block needs its own name", at)
  regNames[b.name] = newLit(b.kind)
  regAt[b.name] = newLit(at.where)
  regLines.add newLit(b.canonical)

proc recordImpl(name, body: NimNode): NimNode {.compileTime.} =
  let fields = parseFields("record " & $name, body)
  register Block(kind: "record", name: $name, fields: fieldsText(fields)), name
  objectDef(name, fields)

macro record*(name, body: untyped): untyped =
  ## A plain value type that events, commands and views may carry.
  guard recordImpl(name, body)

proc eventImpl(name, body: NimNode): NimNode {.compileTime.} =
  let fields = parseFields("event " & $name, body)
  register Block(kind: "event", name: $name, fields: fieldsText(fields)), name
  objectDef(name, fields)

macro event*(name, body: untyped): untyped =
  ## An immutable fact. Its schema is the Nim object type this generates.
  guard eventImpl(name, body)

macro unlistedEmit*(cmd: static string, e: typed): untyped =
  ## What `emit` of an event that `produces` does not list turns into: an error on the `emit` line.
  failAt("command " & cmd & " emits " & e.getTypeInst.repr & ", which its `produces` line does not list;" &
         " add " & e.getTypeInst.repr & " to `produces` (and to the model line), or do not emit it", e)

macro unlistedIssue*(procName: static string, c: typed): untyped =
  ## What `issue` of a command that `issues` does not list turns into: an error on the `issue` line.
  failAt("processor " & procName & " issues " & c.getTypeInst.repr & ", which its `issues` line does not list;" &
         " add " & c.getTypeInst.repr & " to `issues` (and to the model line), or do not issue it", c)

proc commandImpl(name, body: NimNode): NimNode {.compileTime.} =
  let n = $name
  var fields: seq[FieldDef]
  var reads, produces, refuses: seq[string]
  var readsAt, producesAt: seq[NimNode]
  var decideBody, decideAt: NimNode
  for st in body:
    if st.kind == nnkCall and $st[0] == "fields": fields = parseFields("command " & n, st[1])
    elif st.kind == nnkCall and $st[0] == "decide": (decideBody = st[1]; decideAt = st)
    elif st.kind == nnkCommand and $st[0] == "reads": (reads = st.names; readsAt = st.nodes)
    elif st.kind == nnkCommand and $st[0] == "produces": (produces = st.names; producesAt = st.nodes)
    elif st.kind == nnkCommand and $st[0] == "refuses": refuses = st.names
    else: bail("command " & n & ": expected fields:, reads, produces, refuses or decide:, found `" & st[0].repr & "`", st)
  if decideBody.isNil: bail("command " & n & " has no decide: section; add `decide:` with the rules, ending in `emit` or `refuse`", name)
  register Block(kind: "command", name: n, fields: fieldsText(fields),
                 edges: @[("reads", reads), ("produces", produces), ("refuses", refuses)]), name
  regCommands.add newLit(n & " " & reads.join(","))
  result = newStmtList(objectDef(name, fields))
  var prelude = newStmtList()
  if refuses.len > 0:
    result.add relocate(parseStmt("type " & n & "Refusal* = enum " & refuses.join(", ")), name)
    prelude.add relocate(parseStmt("template refuse(refusal: " & n & "Refusal, msg: string) {.used.} =\n" &
                "  return Decision(refused: true, code: $refusal, message: msg)\n"), decideAt)
  for i, p in produces:   # a misspelt event name is reported on its own spot in the `produces` line
    prelude.add relocate(parseStmt("template emit(e: " & p & ") {.used.} = result.events.add envelopeOf(\"" & p & "\", e)\n"), producesAt[i])
  prelude.add relocate(parseStmt("template emit[T](e: T) {.used.} = unlistedEmit(\"" & n & "\", e)\n"), decideAt)
  var params = @[ident"Decision", newIdentDefs(ident"cmd", ident n)]
  for r in reads: params.add newIdentDefs(ident lowerFirst(r), newEmptyNode())
  params.add newIdentDefs(ident"ctx", ident"Ctx")
  # the func's own position is the user's `decide:` line, so "'decide' can have side effects" lands there
  let fn = relocate(newProc(postfix(ident"decide", "*"), params, newEmptyNode(), nnkFuncDef, pure()), decideAt)
  for i in 0 ..< reads.len: fn[3][i + 2][1] = readsAt[i]   # a misspelt view name is reported on the `reads` line
  fn[6] = newStmtList(prelude, decideBody)
  result.add fn

macro command*(name, body: untyped): untyped =
  ## A request to change state. `decide` becomes a `func`: it cannot read a clock, a file or a
  ## global, and it can only `emit` the events listed under `produces`.
  guard commandImpl(name, body)

proc viewImpl(name, body: NimNode): NimNode {.compileTime.} =
  let n = $name
  var fields: seq[FieldDef]
  var consumes: seq[string]
  result = newStmtList()
  var folds = newStmtList()
  for st in body:
    if st.kind == nnkCall and $st[0] == "state": fields = parseFields("view " & n, st[1])
    elif st.kind == nnkCommand and $st[0] == "on" and st.len == 3:
      let ev = st[1].repr
      if ev in consumes: bail("view " & n & " handles " & ev & " twice; merge the two `on " & ev & ":` bodies into one", st)
      consumes.add ev
      regViewOn.add newLit(n & " " & ev)
      let fn = relocate(newProc(postfix(ident"evolve", "*"),
        [newEmptyNode(), newIdentDefs(ident"state", newNimNode(nnkVarTy).add(ident n)),
         newIdentDefs(ident"e", newEmptyNode())], newEmptyNode(), nnkFuncDef, pure()), st)
      fn[3][2][1] = st[1]     # the event's type is the user's own node
      fn[6] = st[2]
      folds.add fn
    else: bail("view " & n & ": expected state: or `on Event:`, found `" & st[0].repr & "`", st)
  register Block(kind: "view", name: n, fields: fieldsText(fields), edges: @[("consumes", consumes)]), name
  regViews.add newLit(n)
  result.add objectDef(name, fields)
  result.add folds

macro view*(name, body: untyped): untyped =
  ## A fold over events. Each `on Event:` becomes a `func`, so a view cannot do I/O either.
  guard viewImpl(name, body)

proc queryImpl(name, body: NimNode): NimNode {.compileTime.} =
  let n = $name
  var fields: seq[FieldDef]
  var reads: seq[string]
  var readsAt: seq[NimNode]
  var returns, answerBody, answerAt: NimNode
  for st in body:
    if st.kind == nnkCall and $st[0] == "fields": fields = parseFields("query " & n, st[1])
    elif st.kind == nnkCall and $st[0] == "answer": (answerBody = st[1]; answerAt = st)
    elif st.kind == nnkCommand and $st[0] == "reads": (reads = st.names; readsAt = st.nodes)
    elif st.kind == nnkCommand and $st[0] == "returns": returns = st[1]
    else: bail("query " & n & ": expected fields:, reads, returns or answer:, found `" & st[0].repr & "`", st)
  if answerBody.isNil or returns.isNil:
    bail("query " & n & " needs returns and answer:; add " &
          (if returns.isNil: "`returns Type`" else: "") & (if returns.isNil and answerBody.isNil: " and " else: "") &
          (if answerBody.isNil: "`answer:` with the expression that builds it" else: ""), name)
  register Block(kind: "query", name: n, fields: fieldsText(fields),
                 edges: @[("reads", reads), ("returns", @[neutralType(returns)])]), name
  regQueries.add newLit(n & " " & reads.join(","))
  var params = @[newEmptyNode(), newIdentDefs(ident"q", ident n)]   # the return type is the user's own node: set below
  for r in reads: params.add newIdentDefs(ident lowerFirst(r), newEmptyNode())
  let fn = relocate(newProc(postfix(ident"answer", "*"), params, newEmptyNode(), nnkFuncDef, pure()), answerAt)
  for i in 0 ..< reads.len: fn[3][i + 2][1] = readsAt[i]
  fn[3][0] = returns
  fn[6] = answerBody
  result = newStmtList(objectDef(name, fields), fn)

macro query*(name, body: untyped): untyped =
  ## Reads views, returns data, changes nothing: views arrive as immutable parameters of a `func`.
  guard queryImpl(name, body)

proc processorImpl(name, body: NimNode): NimNode {.compileTime.} =
  let n = $name
  var issues, consumes: seq[string]
  var issuesNodes, ons: seq[NimNode]
  var issuesAt: NimNode = name
  for st in body:
    if st.kind == nnkCommand and $st[0] == "issues": (issues = st.names; issuesNodes = st.nodes; issuesAt = st)
    elif st.kind == nnkCommand and $st[0] == "on" and st.len == 3: ons.add st
    else: bail("processor " & n & ": expected issues or `on Event:`, found `" & st[0].repr & "`", st)
  result = newStmtList(relocate(parseStmt("type " & n & "* = object"), name))
  proc prelude(): NimNode =
    result = newStmtList()
    for i, c in issues:   # a misspelt command name is reported on its own spot in the `issues` line
      result.add relocate(parseStmt("template issue(c: " & c & ") {.used.} = issueCb(\"" & c & "\", %c)\n"), issuesNodes[i])
    result.add relocate(parseStmt("template issue[T](c: T) {.used.} = unlistedIssue(\"" & n & "\", c)\n"), issuesAt)
  for st in ons:
    consumes.add st[1].repr
    regProcOn.add newLit(n & " " & st[1].repr)
    let fn = relocate(newProc(postfix(ident"react", "*"),
      [newEmptyNode(), newIdentDefs(ident"p", newNimNode(nnkBracketExpr).add(ident"typedesc", ident n)),
       newIdentDefs(ident"e", newEmptyNode()), newIdentDefs(ident"issueCb", ident"IssueProc")],
      newEmptyNode()), st)
    fn[3][2][1] = st[1]
    fn[6] = newStmtList(prelude(), st[2])
    result.add fn
  register Block(kind: "processor", name: n, edges: @[("consumes", consumes), ("issues", issues)]), name

macro processor*(name, body: untyped): untyped =
  ## Reacts to events with side effects (the only block that may have any), and may only `issue`
  ## the commands listed under `issues`.
  guard processorImpl(name, body)

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
  let modelName = modelFile.extractFilename
  var model: Model
  try: model = parseModel(readFile(modelFile), modelName)
  except ModelParseError as e: return failAt("event model " & modelName & " does not parse\n  " & e.msg, appName)
  var codeAt: Table[string, string]
  for name, at in regAt: codeAt[name] = at.strVal
  let (errors, warnings) = checkModel(model, code, modelName, codeAt)
  if defined(eversinceStrict):
    if warnings.len > 0:
      return failAt("event model (strict): lints are errors under -d:eversinceStrict\n  " & warnings.join("\n  "), appName)
  else:
    for w in warnings: warning("event model: " & w, appName)
  if errors.len > 0:
    return failAt("event model " & modelName & " does not match the code" &
                  " (to rewrite its block lines from the code, build once with -d:eversinceWrite)\n  " & errors.join("\n  "), appName)
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
  result = if defined(eversinceNoDispatch): newStmtList() else: relocate(parseStmt(src), appName)
