## Draws the picture of an event model from its model file alone (no code needed).
##
## Layout, top to bottom:
##   - one **group** per screen (the first screen a slice passes through; slices that touch no
##     screen go in a last group, "background work"), in the order the model file first names them;
##   - inside a group, one **band** per slice, in file order;
##   - inside a band, three lanes (who acts / requests and answers / facts), steps left to right.
##     A slice longer than `maxCols` steps continues on a second row of the same band.
##
## The output is plain text, a function of the model file only: no clock, no randomness, no
## floating point. The same file always gives the same bytes, so a diff of two pictures shows
## a change in the model and nothing else. The SVG carries its own style (light and dark) and a
## `<title>` on every box that holds the block's canonical line.

import std/[xmltree, strutils, sequtils]
import ./model

const
  maxCols* = 10           ## steps per row; a longer slice wraps onto the next row of its band
  padX = 18
  gutterW = 92            ## room for the lane labels on the left
  boxH = 46
  boxHTall = 60           ## used for every box when a name needs two lines
  stepGap = 26            ## space between two boxes in a row
  minBoxW = 140
  maxBoxW = 232
  charW = 8               ## width of one character of the name font, a little generous
  laneNames = ["who acts", "requests and answers", "facts"]
  groupHeadH = 34
  bandHeadH = 28
  rowGap = 30             ## strip between two rows of one band; wrap connectors run in it
  bandPad = 14
  background = "background work"

proc lane(kind: string): int =
  case kind
  of "screen", "processor": 0
  of "event": 2
  else: 1

proc splitCamel(name: string, limit: int): seq[string] =
  ## `name` cut into at most two lines of `limit` characters, at a lower-to-upper letter
  ## boundary near the middle when there is one. A name that still does not fit is cut with `…`.
  if name.len <= limit: return @[name]
  var best = -1
  for i in 1 ..< name.len:
    if name[i] in {'A' .. 'Z'} and name[i - 1] notin {'A' .. 'Z'} and i <= limit and name.len - i <= limit:
      if best < 0 or abs(i - name.len div 2) < abs(best - name.len div 2): best = i
  if best < 0:
    best = limit
  let second = name[best .. ^1]
  result = @[name[0 ..< best], if second.len > limit: second[0 ..< limit - 1] & "…" else: second]

proc slug(s: string): string =
  for ch in s.toLowerAscii:
    if ch in {'a' .. 'z', '0' .. '9'}: result.add ch
    elif result.len > 0 and result[^1] != '-': result.add '-'
  result = result.strip(chars = {'-'})
  if result.len == 0: result = "x"

proc groupOf(m: Model, s: model.Slice): string =
  for step in s.steps:
    if m.find(step).kind == "screen": return step
  background

proc titleOf(b: Block, step: string): string =
  if b.name.len == 0: step & " is not in the model file" else: b.canonical

proc styleSheet(dark: bool): string =
  ## The rules for one colour scheme. Plain colours, no custom properties, so that every SVG
  ## renderer (not only browsers) draws it.
  let (bg, ink, dim, rule, lane, edge) =
    if dark: ("#16191d", "#e6e8eb", "#9aa3ad", "#323840", "#1d2126", "#8d96a1")
    else: ("#fbfbf9", "#1b1f24", "#5b6470", "#d5d8dc", "#f1f2f0", "#59626d")
  # kind -> (fill, stroke)
  let kinds =
    if dark:
      [("screen", "#4a3c14", "#d6ad3b"), ("command", "#17324f", "#5ea3ee"), ("event", "#4d2c17", "#f08d4c"),
       ("view", "#173b25", "#52c07c"), ("query", "#2e2650", "#a08aeb"), ("processor", "#2a2e34", "#8d96a1"),
       ("missing", "#4b1d1d", "#ef6b6b")]
    else:
      [("screen", "#fff4d6", "#c79a1c"), ("command", "#dcebff", "#3b82d6"), ("event", "#ffe3d1", "#d9732b"),
       ("view", "#dff4e4", "#2f9e57"), ("query", "#e8e0fb", "#7a5ad1"), ("processor", "#e7e9ec", "#6b7480"),
       ("missing", "#fde0e0", "#c93b3b")]
  result = ".em-bg{fill:" & bg & "}.em-lane{fill:" & lane & "}.em-lane-name,.em-kind,.em-empty{fill:" & dim & "}" &
    ".em-group,.em-title,.em-name{fill:" & ink & "}.em-rule{stroke:" & rule & "}.em-edge{stroke:" & edge & "}.em-head{fill:" & edge & "}"
  for (kind, fill, stroke) in kinds:
    result.add ".em-" & kind & " rect{fill:" & fill & ";stroke:" & stroke & "}"

let style = "<style>\n" &
  ".em-lane-name{font:10px system-ui,sans-serif}.em-group{font:600 15px system-ui,sans-serif}.em-rule{stroke-width:1}\n" &
  ".em-title{font:600 13px system-ui,sans-serif}.em-edge{stroke-width:1.5;fill:none}.em-empty{font:13px system-ui,sans-serif}\n" &
  ".em-box rect{stroke-width:1.5}.em-kind{font:10px system-ui,sans-serif;letter-spacing:.04em}\n" &
  ".em-name{font:600 13px ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}.em-missing rect{stroke-dasharray:4 3}\n" &
  styleSheet(false) & "\n@media (prefers-color-scheme:dark){" & styleSheet(true) & "}\n</style>\n"

proc render*(m: Model): string =
  # --- measure: one box size for the whole picture, so columns line up from band to band
  var longest = 0
  for s in m.slices:
    for step in s.steps: longest = max(longest, step.len)
  let boxW = clamp(longest * charW + 22, minBoxW, maxBoxW)
  let limit = (boxW - 22) div charW
  let tall = m.slices.anyIt(it.steps.anyIt(it.len > limit))
  let bh = if tall: boxHTall else: boxH
  let stepX = boxW + stepGap
  let laneH = bh + 18
  let rowH = 3 * laneH + 10
  var widest = 1
  for s in m.slices: widest = max(widest, min(s.steps.len, maxCols))
  let w = gutterW + padX + widest * stepX - stepGap + padX

  # --- group the slices by screen, in order of first appearance
  var groups: seq[tuple[name: string, slices: seq[int]]]
  for i, s in m.slices:
    let g = groupOf(m, s)
    var at = -1
    for j, grp in groups:
      if grp.name == g: at = j
    if at < 0:
      groups.add (g, @[i])
    else:
      groups[at].slices.add i
  # background work goes last whatever its position in the file
  for j in 0 ..< groups.len:
    if groups[j].name == background and j != groups.len - 1:
      let bg = groups[j]
      groups.delete j
      groups.add bg
      break

  # --- body, with y running down
  var body = ""
  var y = 0
  var used: seq[string]
  proc uniq(base: string): string =
    result = base
    var n = 2
    while result in used:
      result = base & "-" & $n
      inc n
    used.add result
  if m.slices.len == 0:
    body.add "<text class=\"em-empty\" x=\"" & $padX & "\" y=\"28\">The model file has no slices yet.</text>\n"
    y = 48
  for grp in groups:
    let gid = uniq("group-" & slug(grp.name))
    body.add "<g class=\"em-group-box\" id=\"" & gid & "\">\n"
    body.add "<text class=\"em-group\" x=\"" & $padX & "\" y=\"" & $(y + 22) & "\">" & xmltree.escape(grp.name) &
      (if grp.name == background: "" else: "  ·  screen") & "</text>\n"
    body.add "<line class=\"em-rule\" x1=\"0\" y1=\"" & $(y + groupHeadH - 6) & "\" x2=\"" & $w & "\" y2=\"" & $(y + groupHeadH - 6) & "\"/>\n"
    y += groupHeadH
    for si in grp.slices:
      let s = m.slices[si]
      let rows = max(1, (s.steps.len + maxCols - 1) div maxCols)
      let bandH = bandHeadH + rows * rowH + (rows - 1) * rowGap + bandPad
      body.add "<g transform=\"translate(0 " & $y & ")\" id=\"" & uniq("slice-" & slug(s.name)) & "\">\n"
      body.add "<text class=\"em-title\" x=\"" & $padX & "\" y=\"18\">" & xmltree.escape(s.name) & "</text>\n"
      # lane stripes and their labels, once per row
      for r in 0 ..< rows:
        let rowTop = bandHeadH + r * (rowH + rowGap)
        for l in 0 .. 2:
          if l == 1:
            body.add "<rect class=\"em-lane\" x=\"" & $gutterW & "\" y=\"" & $(rowTop + l * laneH) & "\" width=\"" &
              $(w - gutterW) & "\" height=\"" & $laneH & "\"/>\n"
          body.add "<text class=\"em-lane-name\" x=\"" & $padX & "\" y=\"" & $(rowTop + l * laneH + laneH div 2 + 3) & "\">" &
            laneNames[l] & "</text>\n"
      # positions
      var pts: seq[tuple[x, y: int]]
      var blocks: seq[Block]
      for j, step in s.steps:
        let b = m.find(step)
        blocks.add b
        let row = j div maxCols
        let col = j mod maxCols
        let k = if b.name.len == 0: "?" else: b.kind
        pts.add (gutterW + padX + col * stepX,
                 bandHeadH + row * (rowH + rowGap) + lane(k) * laneH + (laneH - bh) div 2)
      # edges first, so boxes sit on top of them
      for j in 0 ..< pts.len - 1:
        let (ax, ay) = pts[j]
        let (bx, by) = pts[j + 1]
        if j div maxCols == (j + 1) div maxCols:
          body.add "<line class=\"em-edge\" marker-end=\"url(#em-arrow)\" x1=\"" & $(ax + boxW) & "\" y1=\"" &
            $(ay + bh div 2) & "\" x2=\"" & $(bx - 3) & "\" y2=\"" & $(by + bh div 2) & "\"/>\n"
        else:
          # wrap: out of the bottom of the last box of a row, along the strip, into the top of the next
          let strip = bandHeadH + ((j div maxCols) + 1) * rowH + (j div maxCols) * rowGap + rowGap div 2
          body.add "<path class=\"em-edge\" marker-end=\"url(#em-arrow)\" d=\"M" & $(ax + boxW div 2) & " " & $(ay + bh) &
            " V" & $strip & " H" & $(bx + boxW div 2) & " V" & $(by - 3) & "\"/>\n"
      for j, step in s.steps:
        let b = blocks[j]
        let (x, py) = pts[j]
        let missing = b.name.len == 0
        let kind = if missing: "missing" else: b.kind
        let lines = splitCamel(step, limit)
        body.add "<g class=\"em-box em-" & kind & "\"><title>" & xmltree.escape(titleOf(b, step)) & "</title><rect x=\"" & $x &
          "\" y=\"" & $py & "\" width=\"" & $boxW & "\" height=\"" & $bh & "\" rx=\"7\"/>" &
          "<text class=\"em-kind\" x=\"" & $(x + 9) & "\" y=\"" & $(py + 15) & "\">" & (if missing: "NOT IN MODEL" else: b.kind.toUpperAscii) & "</text>"
        for li, text in lines:
          body.add "<text class=\"em-name\" x=\"" & $(x + 9) & "\" y=\"" & $(py + 33 + li * 15) & "\">" & xmltree.escape(text) & "</text>"
        body.add "</g>\n"
      body.add "</g>\n"
      y += bandH
    body.add "</g>\n"
  result = "<svg class=\"em-pic\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " & $w & " " & $y &
    "\" width=\"" & $w & "\" height=\"" & $y & "\" role=\"img\" aria-label=\"Event model, grouped by screen, one band per slice\">\n" &
    style &
    "<defs><marker id=\"em-arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\">" &
    "<path d=\"M0 0L10 5L0 10z\" class=\"em-head\"/></marker></defs>\n" &
    "<rect class=\"em-bg\" x=\"0\" y=\"0\" width=\"" & $w & "\" height=\"" & $y & "\"/>\n" &
    body & "</svg>\n"
