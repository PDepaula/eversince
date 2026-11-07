## The picture is drawn from the model file alone: one band per slice.
import std/[unittest, os, strutils]
import eversince, eversince/picture

suite "picture":
  test "the desk model renders one band per slice":
    let m = parseModel(readFile(currentSourcePath().parentDir / ".." / "examples" / "desk" / "desk.em"))
    let svg = render(m)
    check svg.startsWith("<svg")
    check svg.strip.endsWith("</svg>")
    check svg.count("<g transform=") == m.slices.len
    for s in m.slices:
      check s.name in svg
