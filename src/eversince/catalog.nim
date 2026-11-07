## The catalogue: the model file as a list an agent reads at the start of a session, instead of
## opening source files. One line per block, grouped by kind, sorted by name, with what each block
## is connected to worked out from the other blocks.
##
## The text is a function of the model file only, so the same file always gives the same bytes,
## whatever the order of its lines. A comment at the end of a block line (`event Said ... # one
## line of meaning`) is added to that block's line as its meaning.

import std/[strutils, sequtils, algorithm, tables]
import ./model

const
  kindOrder = ["screen", "command", "event", "view", "query", "processor", "record"]
  kindPlural = ["screens", "commands", "events", "views", "queries", "processors", "records"]
  kindMeaning = [
    ("screen", "where a person acts and looks: the queries it shows and the commands it offers"),
    ("command", "a request to change state: decides from the views it reads, produces events or refuses with a code"),
    ("event", "an immutable fact: something that happened"),
    ("view", "what the app remembers: a fold of the events it consumes"),
    ("query", "a question answered from views; changes nothing"),
    ("processor", "background work that reacts to events and issues commands (the only block with side effects)"),
    ("record", "a plain value type that events, commands and views carry"),
    ("slice", "one story as a path of blocks: screen, command, event, view, query, back to the screen")]

proc meanings(text: string): Table[string, string] =
  ## Name -> the comment at the end of its block line.
  for raw in text.splitLines:
    let parts = raw.split('#', 1)
    if parts.len < 2: continue
    let head = parts[0].split('|')[0].splitWhitespace
    let note = parts[1].strip
    if head.len >= 2 and head[0] != "slice" and note.len > 0: result[head[1]] = note

proc names(m: Model, kinds: openArray[string], key, value: string): seq[string] =
  ## The blocks of those kinds whose edge `key` lists `value`, sorted.
  for b in m.blocks:
    if b.kind in kinds and value in b.edge(key): result.add b.name
  result.sort
  result = result.deduplicate(isSorted = true)

proc list(items: seq[string]): string = items.join(", ")

proc describe(m: Model, b: Block): string =
  ## What the block is, in one line. Edges are the model file's own; the "used by" parts are
  ## found by looking at the other blocks.
  var parts: seq[string]
  proc add(label: string, items: seq[string]) =
    if items.len > 0: parts.add label & " " & list(items)
  case b.kind
  of "screen":
    add "shows", b.edge("queries").sorted
    add "offers", b.edge("commands").sorted
  of "command":
    add "reads", b.edge("reads").sorted
    add "produces", b.edge("produces").sorted
    add "refuses", b.edge("refuses").sorted
    add "on screen", m.names(["screen"], "commands", b.name)
    add "issued by", m.names(["processor"], "issues", b.name)
  of "event":
    add "produced by", m.names(["command"], "produces", b.name)
    add "consumed by", m.names(["view", "processor"], "consumes", b.name)
  of "view":
    add "folds", b.edge("consumes").sorted
    add "read by", m.names(["query", "command"], "reads", b.name)
  of "query":
    add "reads", b.edge("reads").sorted
    add "returns", b.edge("returns")
    add "on screen", m.names(["screen"], "queries", b.name)
  of "processor":
    add "on", b.edge("consumes").sorted
    add "issues", b.edge("issues").sorted
  else:
    for e in b.edges: add e.key, e.vals.sorted
  result = parts.join("; ")

proc catalogText*(m: Model, modelText = ""): string =
  ## The whole catalogue. `modelText` is the model file's text, only used for the comments.
  let notes = meanings(modelText)
  var lines = @["# eversince catalog", "size: " & m.counts, "", "## kinds"]
  for (kind, meaning) in kindMeaning: lines.add "- " & kind & ": " & meaning
  proc section(title: string, bs: seq[Block]) =
    lines.add ""
    lines.add "## " & title & " (" & $bs.len & ")"
    for b in bs.sortedByIt(it.name):
      var line = "- " & b.name
      if b.fields.len > 0: line.add "(" & b.fields.join(" ") & ")"
      let what = describe(m, b)
      if what.len > 0: line.add " - " & what
      if b.name in notes: line.add " - " & notes[b.name]
      lines.add line
  for i, kind in kindOrder:
    let bs = m.blocks.filterIt(it.kind == kind)
    if bs.len > 0: section kindPlural[i], bs
  # kinds the parser accepts but the vocabulary does not name: shown, never hidden
  var others: seq[string]
  for b in m.blocks:
    if b.kind notin kindOrder and b.kind notin others: others.add b.kind
  for kind in others.sorted:
    section kind & " (not in the vocabulary)", m.blocks.filterIt(it.kind == kind)
  if m.slices.len > 0:
    lines.add ""
    lines.add "## slices (" & $m.slices.len & ")"
    for s in m.slices.sortedByIt(it.name):
      lines.add "- " & s.name & ": " & s.steps.join(" -> ")
  result = lines.join("\n") & "\n"
