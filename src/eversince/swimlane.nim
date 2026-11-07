## The swimlane timeline: the picture of an event model that draws every block once.
##
## Lanes, top to bottom: who acts (screens and processors), commands, events, views, queries.
## Time runs left to right: the events are placed in the order they first appear in the slices
## (events no slice mentions follow, by name), and every other block sits near the events it is
## joined to. Each lane is a zigzag of two sub-rows, so a lane of twenty boxes stays narrow.
##
## Arrows are the edges the blocks declare, nothing else (`edges`):
##   command -> event        `produces`        event -> view or processor   `consumes`
##   processor -> command    `issues`          screen -> command            `commands`
##   query -> screen         `queries`         view -> command or query     `reads`
## The `reads` arrows are many (every command reads the same few views) and are left out unless
## asked for. Slices are not drawn: they only decide the order of the events.
##
## Records are value types, not part of the story, and are not drawn. A block of a kind outside
## the vocabulary, and a slice step that names no block, are not drawn either (`check` and
## `catalog` report them).
##
## The output is a function of the model file's content only: it does not depend on the order
## of the block lines, and it uses no clock, no randomness and no floating point, so the same
## model gives the same bytes on every machine.

import std/[strutils, sequtils, algorithm, tables, sets, xmltree, unicode]
import std/json
import ./[model, picstyle, swimpage]

type
  SwimOptions* = object
    fields*: bool     ## show each block's fields and a command's refusal codes, not only its name
    spacious*: bool   ## looser spacing and larger text
    reads*: bool      ## also draw the dashed `reads` arrows (a view read by a command or query)
  Edge* = object
    src*, dst*, kind*: string   ## kind: produces, consumes, issues, offers, shows or reads

  SwimStyle = object
    nameFs, fieldFs, tagFs, padX, gapX, laneGap, boxH, lineH: int

  Placed = object
    x, y, w, h: int

const
  drawnKinds* = ["screen", "processor", "command", "event", "view", "query"]
  laneLabels = [("who acts", "screens, processors"), ("commands", "requests"), ("events", "facts"),
                ("views", "what is remembered"), ("queries", "questions")]
  charPct = 61          ## width of one character of the monospace font, in percent of its size
  maxFieldChars = 28    ## a longer field line is cut with `…`
  gutterW = 128         ## room for the lane labels on the left
  sgap = 12             ## between the two sub-rows of a lane
  zigPct = 58           ## events are this percent of a box step apart

proc lane(kind: string): int =
  case kind
  of "screen", "processor": 0
  of "command": 1
  of "event": 2
  of "view": 3
  else: 4

proc styleOf(o: SwimOptions): SwimStyle =
  if o.spacious:
    SwimStyle(nameFs: 14, fieldFs: 12, tagFs: 10, padX: 11, gapX: 34, laneGap: 96, boxH: 40, lineH: 16)
  else:
    SwimStyle(nameFs: 12, fieldFs: 10, tagFs: 9, padX: 8, gapX: 14, laneGap: 44, boxH: 28, lineH: 14)

proc declared(m: Model): OrderedTable[string, Block] =
  ## The drawn blocks by name, sorted by name; the first declaration of a name wins.
  var byName: Table[string, Block]
  for b in m.blocks:
    if b.kind in drawnKinds and b.name notin byName: byName[b.name] = b
  for name in toSeq(byName.keys).sorted:
    result[name] = byName[name]

proc edges*(m: Model): seq[Edge] =
  ## Every arrow of the picture: one for each edge a block declares to another drawn block of the
  ## right kind, sorted by source, target and kind, without repeats.
  let blocks = declared(m)
  var seen = initHashSet[(string, string, string)]()
  var found: seq[Edge]
  proc add(src, dst, kind: string) =
    if (src, dst, kind) notin seen:
      seen.incl (src, dst, kind)
      found.add Edge(src: src, dst: dst, kind: kind)
  proc kindOf(name: string): string =
    if name in blocks: blocks[name].kind else: ""
  for name, b in blocks:
    case b.kind
    of "command":
      for x in b.edge("produces"):
        if kindOf(x) == "event": add name, x, "produces"
      for x in b.edge("reads"):
        if kindOf(x) == "view": add x, name, "reads"
    of "view":
      for x in b.edge("consumes"):
        if kindOf(x) == "event": add x, name, "consumes"
    of "query":
      for x in b.edge("reads"):
        if kindOf(x) == "view": add x, name, "reads"
    of "processor":
      for x in b.edge("consumes"):
        if kindOf(x) == "event": add x, name, "consumes"
      for x in b.edge("issues"):
        if kindOf(x) == "command": add name, x, "issues"
    of "screen":
      for x in b.edge("commands"):
        if kindOf(x) == "command": add name, x, "offers"
      for x in b.edge("queries"):
        if kindOf(x) == "query": add x, name, "shows"
    else: discard
  found.sort proc (a, b: Edge): int = cmp((a.src, a.dst, a.kind), (b.src, b.dst, b.kind))
  found

proc eventOrder(m: Model, blocks: OrderedTable[string, Block]): seq[string] =
  ## Events in the order the slices first mention them, then the ones no slice mentions, by name.
  for s in m.slices:
    for step in s.steps:
      if step in blocks and blocks[step].kind == "event" and step notin result: result.add step
  for name, b in blocks:
    if b.kind == "event" and name notin result: result.add name

proc push[K, V](t: var Table[K, seq[V]], key: K, value: V) =
  if t.hasKey(key): t[key].add value
  else: t[key] = @[value]

proc clip(s: string, n = maxFieldChars): string =
  ## `s` cut to `n` characters, counted as characters and not bytes.
  let chars = toRunes(s)
  if chars.len <= n: s else: $chars[0 ..< n - 1] & "…"

proc detailLines(b: Block): seq[tuple[refusal: bool, text: string]] =
  ## What a box shows below its name: the fields, then a command's refusal codes.
  for f in b.fields: result.add (false, clip(f))
  if b.kind == "command" and b.edge("refuses").len > 0:
    result.add (true, clip("refuses " & b.edge("refuses").join(",")))

proc textW(chars, fontSize: int): int = chars * fontSize * charPct div 100

proc colourRules(dark: bool): string =
  let p = palette(dark)
  result = ".em-bg{fill:" & p.bg & "}.em-lane{fill:" & p.lane & "}" &
    ".em-lane-name,.em-lane-sub,.em-kind,.em-field,.em-empty{fill:" & p.dim & "}.em-name{fill:" & p.ink & "}" &
    ".em-edge{stroke:" & p.edge & "}.em-head{fill:" & p.edge & "}"
  for (kind, fill, stroke) in p.kinds:
    result.add ".em-" & kind & " rect{fill:" & fill & ";stroke:" & stroke & "}"
    if kind == "command": result.add ".em-refusal{fill:" & stroke & "}"

proc swimRules*(): string =
  ## The style rules of the swimlane picture, light and dark. A page that embeds the picture
  ## without its own `<style>` (`renderSwimlane(..., standalone = false)`) puts these in its stylesheet.
  ".em-lane-name{font:600 11px system-ui,sans-serif}.em-lane-sub{font:10px system-ui,sans-serif}.em-empty{font:13px system-ui,sans-serif}\n" &
  ".em-lane{opacity:.55}.em-edge{fill:none;stroke-width:1.2;opacity:.55}.em-reads{stroke-dasharray:5 4}.em-box rect{stroke-width:1.5}\n" &
  ".em-name{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-weight:600}.em-field{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}\n" &
  ".em-kind{font-family:system-ui,sans-serif;letter-spacing:.05em}.em-refusal{font-style:italic}\n" &
  colourRules(false) & "\n@media (prefers-color-scheme:dark){" & colourRules(true) & "}\n"

proc swimStyle(): string = "<style>\n" & swimRules() & "</style>\n"

proc renderSwimlane*(m: Model, o = SwimOptions(), idPrefix = "em", standalone = true): string =
  ## The swimlane picture as SVG. `idPrefix` starts every `id`, so that several pictures can sit in
  ## one page; with `standalone = false` the SVG has no `<style>` and no fixed size (a page styles
  ## and sizes it).
  let blocks = declared(m)
  let st = styleOf(o)
  let all = edges(m)
  proc svgOpen(w, h: int): string =
    result = "<svg class=\"em-pic em-swim\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " & $w & " " & $h & "\""
    if standalone: result.add " width=\"" & $w & "\" height=\"" & $h & "\""
    result.add " data-w=\"" & $w & "\" data-h=\"" & $h & "\" role=\"img\" aria-label=\"Event model, swimlane timeline" &
      (if o.fields: ", with fields" else: "") & "\">\n"
  if blocks.len == 0:
    let (w, h) = (360, 56)
    return svgOpen(w, h) & (if standalone: swimStyle() else: "") &
      "<rect class=\"em-bg\" x=\"0\" y=\"0\" width=\"" & $w & "\" height=\"" & $h & "\"/>\n" &
      "<text class=\"em-empty\" x=\"18\" y=\"32\">The model file has no blocks to draw yet.</text>\n</svg>\n"

  # --- one box width for every block, so that columns line up
  var w = 0
  for name, b in blocks:
    w = max(w, textW(name.runeLen, st.nameFs))
    if o.fields:
      for (_, text) in detailLines(b): w = max(w, textW(text.runeLen, st.fieldFs))
  w += 2 * st.padX
  let step = w + st.gapX
  proc heightOf(b: Block): int =
    if not o.fields: st.boxH
    else: 12 + st.tagFs + 8 + st.nameFs + 6 + detailLines(b).len * st.lineH + 6

  # --- time: events first, in story order; the rest near the events they are joined to
  var x: Table[string, int]
  for i, e in eventOrder(m, blocks): x[e] = i * step * zigPct div 100
  var nbrs: Table[string, seq[string]]
  for e in all:
    nbrs.push e.src, e.dst
    nbrs.push e.dst, e.src
  proc place(kind: string, near: openArray[string]) =
    for name, b in blocks:
      if b.kind != kind: continue
      var sum, n = 0
      for other in nbrs.getOrDefault(name):
        if other in x and blocks[other].kind in near:
          sum += x[other]
          inc n
      x[name] = if n > 0: (sum + n div 2) div n else: 0
  place "command", ["event"]
  place "view", ["event"]
  place "query", ["view"]
  place "processor", ["event", "command"]
  place "screen", ["command", "query"]

  # --- lane by lane: sort by wanted x, push right so that boxes of one sub-row do not touch
  var inLane: Table[int, seq[string]]
  for name, b in blocks: inLane.push lane(b.kind), name
  var sub: Table[string, int]
  var laneIds = toSeq(inLane.keys).sorted
  for l in laneIds:
    inLane[l].sort proc (a, b: string): int = cmp((x[a], a), (x[b], b))
    for i, name in inLane[l]:
      if i > 0: x[name] = max(x[name], x[inLane[l][i - 1]] + step div 2)
      sub[name] = i mod 2
  var rowH, laneH, laneY: Table[int, int]
  for l in laneIds:
    for name in inLane[l]: rowH[l] = max(rowH.getOrDefault(l), heightOf(blocks[name]))
    laneH[l] = 2 * rowH[l] + sgap
  let pad = st.laneGap div 2
  let top = pad + 8
  var y = 0
  for l in laneIds:
    laneY[l] = y
    y += laneH[l] + st.laneGap
  var minX = high(int)
  for name in blocks.keys: minX = min(minX, x[name])
  var pos: Table[string, Placed]
  var right = 0
  for name, b in blocks:
    let l = lane(b.kind)
    let h = heightOf(b)
    pos[name] = Placed(x: x[name] - minX + gutterW, y: top + laneY[l] + sub[name] * (rowH[l] + sgap) + (rowH[l] - h) div 2, w: w, h: h)
    right = max(right, pos[name].x + w)
  let width = right + 30
  let height = top + laneY[laneIds[^1]] + laneH[laneIds[^1]] + pad

  # --- arrows: each leaves a box on the side that faces the other box, and the arrows on one
  # side are spread along it in the order of where they go, so that they do not cross at the box
  let drawn = all.filterIt(it.kind != "reads" or o.reads)
  var parts: seq[string]
  proc edgePaths(group: seq[Edge]): seq[string] =
    var down = newSeq[bool](group.len)
    var ports: Table[string, seq[tuple[other, edge, end2: int]]]
    for i, e in group:
      down[i] = pos[e.dst].y > pos[e.src].y
      ports.push e.src & (if down[i]: "/b" else: "/t"), (pos[e.dst].x + w div 2, i, 0)
      ports.push e.dst & (if down[i]: "/t" else: "/b"), (pos[e.src].x + w div 2, i, 1)
    var px: Table[(int, int), int]
    for key, list in ports.mpairs:
      list.sort
      let name = key[0 ..< key.len - 2]
      for k, (_, i, end2) in list:
        px[(i, end2)] = pos[name].x + w * (k + 1) div (list.len + 1)
    for i, e in group:
      let (a, b) = (pos[e.src], pos[e.dst])
      let (x1, x2) = (px[(i, 0)], px[(i, 1)])
      let y1 = if down[i]: a.y + a.h else: a.y
      let y2 = if down[i]: b.y else: b.y + b.h
      let c = max(26, abs(y2 - y1) div 2) * (if down[i]: 1 else: -1)
      result.add "<path class=\"em-edge em-" & e.kind & "\" data-from=\"" & xmltree.escape(e.src) & "\" data-to=\"" &
        xmltree.escape(e.dst) & "\" data-kind=\"" & e.kind & "\" marker-end=\"url(#" & idPrefix & "-arrow)\" d=\"M" & $x1 & " " & $y1 &
        "C" & $x1 & " " & $(y1 + c) & " " & $x2 & " " & $(y2 - c) & " " & $x2 & " " & $y2 & "\"><title>" &
        xmltree.escape(e.src) & " → " & xmltree.escape(e.dst) & " (" & e.kind & ")</title></path>"

  # --- the SVG, back to front: lanes, arrows, boxes
  parts.add svgOpen(width, height)
  if standalone: parts.add swimStyle()
  parts.add "<defs><marker id=\"" & idPrefix & "-arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"6\" markerHeight=\"6\" orient=\"auto\">" &
    "<path d=\"M0 0L10 5L0 10z\" class=\"em-head\"/></marker></defs>\n"
  parts.add "<rect class=\"em-bg\" x=\"0\" y=\"0\" width=\"" & $width & "\" height=\"" & $height & "\"/>\n"
  for l in laneIds:
    let y0 = top + laneY[l] - pad + 2
    let h0 = laneH[l] + st.laneGap - 4
    let mid = y0 + h0 div 2
    parts.add "<g class=\"em-stripe\"><rect class=\"em-lane\" x=\"0\" y=\"" & $y0 & "\" width=\"" & $width & "\" height=\"" & $h0 & "\"/>" &
      "<text class=\"em-lane-name\" x=\"14\" y=\"" & $(mid - 2) & "\">" & laneLabels[l][0] & "</text>" &
      "<text class=\"em-lane-sub\" x=\"14\" y=\"" & $(mid + 12) & "\">" & laneLabels[l][1] & "</text></g>\n"
  parts.add "<g class=\"em-edges\">"
  parts.add edgePaths(drawn.filterIt(it.kind != "reads")).join("\n")
  if o.reads: parts.add edgePaths(drawn.filterIt(it.kind == "reads")).join("\n")
  parts.add "</g>\n<g class=\"em-nodes\">\n"
  for name, b in blocks:
    let p = pos[name]
    var g = "<g class=\"em-box em-" & b.kind & "\" data-name=\"" & xmltree.escape(name) & "\" transform=\"translate(" & $p.x & " " & $p.y &
      ")\"><title>" & xmltree.escape(b.canonical) & "</title><rect width=\"" & $p.w & "\" height=\"" & $p.h & "\" rx=\"6\"/>"
    if not o.fields:
      g.add "<text class=\"em-name\" font-size=\"" & $st.nameFs & "\" x=\"" & $(p.w div 2) & "\" y=\"" &
        $(p.h div 2 + st.nameFs * 35 div 100) & "\" text-anchor=\"middle\">" & xmltree.escape(name) & "</text>"
    else:
      let tagY = 10 + st.tagFs
      let nameY = tagY + 6 + st.nameFs
      g.add "<text class=\"em-kind\" font-size=\"" & $st.tagFs & "\" x=\"" & $st.padX & "\" y=\"" & $tagY & "\">" & b.kind.toUpperAscii & "</text>"
      g.add "<text class=\"em-name\" font-size=\"" & $st.nameFs & "\" x=\"" & $st.padX & "\" y=\"" & $nameY & "\">" & xmltree.escape(name) & "</text>"
      var fy = nameY + 6
      for (refusal, text) in detailLines(b):
        fy += st.lineH
        g.add "<text class=\"em-field" & (if refusal: " em-refusal" else: "") & "\" font-size=\"" & $st.fieldFs & "\" x=\"" & $st.padX & "\" y=\"" &
          $(fy - 3) & "\">" & xmltree.escape(text) & "</text>"
    g.add "</g>"
    parts.add g
  parts.add "</g>\n</svg>\n"
  result = parts.join("")

proc page*(m: Model, o = SwimOptions(), title = "Event model"): string =
  ## One self-contained HTML page: the swimlane picture with switches for fields and density, the
  ## `reads` arrows, wheel zoom, drag, one-finger pan and two-finger pinch, fit to the window, and
  ## a click on a box or a story to light up its arrows. It loads nothing from the network. All four
  ## drawings (names or fields, compact or spacious) are in the page; `o` says which one shows
  ## first. The page is as deterministic as the picture.
  var variants: seq[string]
  for density in ["c", "s"]:
    for detail in ["n", "f"]:
      let svg = renderSwimlane(m, SwimOptions(fields: detail == "f", spacious: density == "s", reads: true),
                       idPrefix = "v-" & density & "-" & detail, standalone = false)
      variants.add "<div class=\"variant\" data-key=\"" & density & "-" & detail & "\" hidden>" & svg.strip & "</div>"
  var blocks = newJObject()
  let drawnBlocks = declared(m)
  for name, b in drawnBlocks: blocks[name] = %*{"kind": b.kind, "line": b.canonical}
  var slices = newJArray()
  for sl in m.slices: slices.add %*{"name": sl.name, "steps": sl.steps}
  var colours = newJObject()
  for (scheme, dark) in [("light", false), ("dark", true)]:
    colours[scheme] = newJObject()
    for (kind, fill, stroke) in palette(dark).kinds: colours[scheme][kind] = %[fill, stroke]
  let data = %*{"blocks": blocks, "edges": edges(m).mapIt(%*{"f": it.src, "t": it.dst, "ty": it.kind}), "slices": slices,
                "counts": m.counts, "init": {"fields": o.fields, "spacious": o.spacious, "reads": o.reads}}
  proc inScript(j: JsonNode): string = ($j).replace("</", "<\\/").replace("<!--", "<\\!--")
  result = pageTemplate
    .replace("<!--TITLE-->", xmltree.escape(title))
    .replace("/*EM-STYLE*/", swimRules())
    .replace("<!--VARIANTS-->", variants.join("\n"))
    .replace("/*COLOURS*/null", inScript(colours))
    .replace("/*DATA*/null", inScript(data))
