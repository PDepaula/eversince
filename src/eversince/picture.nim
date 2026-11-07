## Draws the picture of an event model from its model file alone (no code needed): one band per
## slice, three lanes (who acts / requests and answers / facts), left to right.
## Starting code carried over from the prototype; polish is M1.

import std/xmltree
import ./model

const
  boxW = 138
  boxH = 46
  stepX = 164
  laneY = [34, 100, 166]
  bandH = 236
  padX = 18

proc lane(kind: string): int =
  case kind
  of "screen", "processor": 0
  of "event": 2
  else: 1

proc render*(m: Model): string =
  var widest = 0
  for s in m.slices: widest = max(widest, s.steps.len)
  let w = padX * 2 + widest * stepX - (stepX - boxW)
  let h = m.slices.len * bandH
  result = "<svg class=\"em-pic\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " & $w & " " & $h &
    "\" width=\"" & $w & "\" height=\"" & $h & "\" role=\"img\" aria-label=\"Event model, one band per slice\">\n" &
    "<defs><marker id=\"em-arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\">" &
    "<path d=\"M0 0L10 5L0 10z\" class=\"em-head\"/></marker></defs>\n"
  for i, s in m.slices:
    let top = i * bandH
    result.add "<g transform=\"translate(0 " & $top & ")\">\n"
    if i > 0: result.add "<line class=\"em-rule\" x1=\"0\" y1=\"0\" x2=\"" & $w & "\" y2=\"0\"/>\n"
    result.add "<text class=\"em-title\" x=\"" & $padX & "\" y=\"20\">" & xmltree.escape(s.name) & "</text>\n"
    var pts: seq[tuple[x, y: int]]
    for j, step in s.steps:
      pts.add (padX + j * stepX, laneY[lane(m.find(step).kind)])
    for j in 0 ..< pts.len - 1:
      let (ax, ay) = pts[j]
      let (bx, by) = pts[j + 1]
      result.add "<line class=\"em-edge\" marker-end=\"url(#em-arrow)\" x1=\"" & $(ax + boxW) & "\" y1=\"" &
        $(ay + boxH div 2) & "\" x2=\"" & $(bx - 3) & "\" y2=\"" & $(by + boxH div 2) & "\"/>\n"
    for j, step in s.steps:
      let b = m.find(step)
      let (x, y) = pts[j]
      result.add "<g class=\"em-box em-" & b.kind & "\"><rect x=\"" & $x & "\" y=\"" & $y & "\" width=\"" & $boxW &
        "\" height=\"" & $boxH & "\" rx=\"7\"/>" &
        "<text class=\"em-kind\" x=\"" & $(x + 9) & "\" y=\"" & $(y + 15) & "\">" & b.kind & "</text>" &
        "<text class=\"em-name\" x=\"" & $(x + 9) & "\" y=\"" & $(y + 34) & "\">" & xmltree.escape(b.name) & "</text></g>\n"
    result.add "</g>\n"
  result.add "</svg>\n"
