## The swimlane picture (`pic`, the default layout) and its page (`pic --html`): golden files for
## the desk example and for a copy of Para Studio's real model, what each display flag changes,
## and the rule that every arrow drawn is an edge a block declares.
##
## To accept a change to a golden file (then read the diff before committing):
##   EVERSINCE_UPDATE_GOLDEN=1 nim c -r tests/tswimlane.nim
import std/[unittest, os, strutils, sequtils, algorithm, sets, json]
import eversince, eversince/[picture, swimlane]

let root = currentSourcePath().parentDir / ".."
let deskText = readFile(root / "examples" / "desk" / "desk.em")
let studioText = readFile(root / "tests" / "golden" / "studiodesk.em")
let desk = parseModel(deskText)
let studio = parseModel(studioText)

proc lf(s: string): string = s.replace("\r\n", "\n")

proc golden(name, got: string) =
  let path = root / "tests" / "golden" / name
  if getEnv("EVERSINCE_UPDATE_GOLDEN").len > 0: writeFile(path, got)
  check lf(readFile(path)) == got

type Arrow = tuple[src, dst, kind: string]

proc attr(tag, name: string): string =
  let at = tag.find(" " & name & "=\"")
  if at < 0: return ""
  let start = at + name.len + 3
  tag[start ..< tag.find('"', start)].replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")

proc drawnArrows(svg: string): seq[Arrow] =
  for part in svg.split("<path class=\"em-edge")[1 .. ^1]:
    let tag = part[0 ..< part.find('>')]
    result.add (tag.attr("data-from"), tag.attr("data-to"), tag.attr("data-kind"))

proc drawnBoxes(svg: string): seq[string] =
  for part in svg.split("<g class=\"em-box")[1 .. ^1]:
    result.add part[0 ..< part.find('>')].attr("data-name")

proc boxX(svg, name: string): int =
  ## The x of a box: `translate(x y)` of its group.
  let at = svg.find("data-name=\"" & name & "\" transform=\"translate(")
  doAssert at >= 0, name
  let start = svg.find("translate(", at) + len("translate(")
  parseInt(svg[start ..< svg.find(' ', start)])

proc viewBox(svg: string): tuple[w, h: int] =
  let tag = svg[0 ..< svg.find('>')]
  (parseInt(tag.attr("data-w")), parseInt(tag.attr("data-h")))

proc declaredArrows(m: Model): HashSet[Arrow] =
  ## Written out from the vocabulary (spec/02-model-file.md, "Slice rules"), without `edges`: the
  ## edge a block declares, as the arrow between it and the block it names.
  let kinds = m.blocks.mapIt((it.name, it.kind))
  proc isA(name, kind: string): bool = (name, kind) in kinds
  for b in m.blocks:
    case b.kind
    of "command":
      for e in b.edge("produces"): (if e.isA("event"): result.incl (b.name, e, "produces"))
      for v in b.edge("reads"): (if v.isA("view"): result.incl (v, b.name, "reads"))
    of "view":
      for e in b.edge("consumes"): (if e.isA("event"): result.incl (e, b.name, "consumes"))
    of "query":
      for v in b.edge("reads"): (if v.isA("view"): result.incl (v, b.name, "reads"))
    of "processor":
      for e in b.edge("consumes"): (if e.isA("event"): result.incl (e, b.name, "consumes"))
      for c in b.edge("issues"): (if c.isA("command"): result.incl (b.name, c, "issues"))
    of "screen":
      for c in b.edge("commands"): (if c.isA("command"): result.incl (b.name, c, "offers"))
      for q in b.edge("queries"): (if q.isA("query"): result.incl (q, b.name, "shows"))
    else: discard

suite "swimlane picture: golden files":
  test "the desk picture is the golden file":
    golden "desk.svg", renderSwimlane(desk)

  test "the desk picture with fields and spacing is the golden file":
    golden "desk.fields.spacious.svg", renderSwimlane(desk, SwimOptions(fields: true, spacious: true))

  test "Para Studio's model (a copy of studiodesk.em) is the golden file":
    golden "studiodesk.svg", renderSwimlane(studio)

  test "pic draws the swimlane unless asked for the stories":
    check render(desk) == renderSwimlane(desk)
    check "em-swim" in render(desk)
    check "em-swim" notin render(desk, layoutStories)
    check render(desk, layoutStories).count("<g transform=") == desk.slices.len

suite "swimlane picture: what it draws":
  test "every non-record block is drawn once, and records are not":
    for m in [desk, studio]:
      let boxes = drawnBoxes(renderSwimlane(m)).sorted
      let want = m.blocks.filterIt(it.kind in drawnKinds).mapIt(it.name).sorted
      check boxes == want
      check m.blocks.anyIt(it.kind == "record")
      for b in m.blocks:
        if b.kind == "record": check b.name notin boxes

  test "lanes run who acts, commands, events, views, queries from the top":
    let svg = renderSwimlane(desk)
    proc y(name: string): int =
      let at = svg.find("data-name=\"" & name & "\" transform=\"translate(")
      let s1 = svg.find(' ', svg.find("translate(", at)) + 1
      parseInt(svg[s1 ..< svg.find(')', s1)])
    check y("ChatPanel") < y("SendMessage")
    check y("TurnRunner") < y("SendMessage")
    check y("SendMessage") < y("TurnStarted")
    check y("TurnStarted") < y("Desk")
    check y("Desk") < y("DeskState")

  test "time runs left to right: events in the order the slices first mention them":
    let svg = renderSwimlane(desk)
    # slices 1, 2, 3, 4 and 5 first mention these events in this order
    let order = ["TurnStarted", "Said", "TurnEnded", "StopRequested", "StepStarted", "StepEnded", "AgentPicked", "ConversationCleared"]
    for i in 1 ..< order.len:
      check boxX(svg, order[i - 1]) < boxX(svg, order[i])
    # an event no slice mentions comes after all of them
    check boxX(svg, "MessageSent") > boxX(svg, "ConversationCleared")

  test "the first slice to mention an event places it, wherever the blocks are listed":
    let moved = parseModel("slice early : SendMessage -> MessageSent\n" & deskText)
    check boxX(renderSwimlane(moved), "MessageSent") < boxX(renderSwimlane(moved), "TurnStarted")

  test "the order of the block lines does not change the picture":
    let blocks = deskText.splitLines.filterIt(not it.startsWith("slice"))
    let slices = deskText.splitLines.filterIt(it.startsWith("slice"))
    check renderSwimlane(parseModel(blocks.reversed.join("\n") & "\n" & slices.join("\n"))) == renderSwimlane(desk)

  test "the same model gives the same bytes":
    check renderSwimlane(studio) == renderSwimlane(studio)
    check renderSwimlane(studio, SwimOptions(fields: true)) == renderSwimlane(studio, SwimOptions(fields: true))

  test "the picture holds no floating point number and no machine path":
    let svg = renderSwimlane(studio, SwimOptions(fields: true, spacious: true, reads: true))
    for part in svg.split("<path class=\"em-edge")[1 .. ^1]:
      let d = part[part.find(" d=\"") + 4 ..< part.find("\"><title>")]
      check '.' notin d
    check root notin svg

  test "a model with no blocks, a ghost step and odd names still gives a valid picture":
    for text in ["", "slice a : Ghost\n", "event A<b&c x:int\nslice s : A<b&c\n", "record R x:int\n"]:
      let svg = renderSwimlane(parseModel(text))
      check svg.startsWith("<svg") and svg.strip.endsWith("</svg>")
    check "no blocks to draw" in renderSwimlane(parseModel(""))
    let odd = renderSwimlane(parseModel("event A<b&c x:int\n"))
    check "A&lt;b&amp;c" in odd and "A<b" notin odd

  test "the picture is plain SVG: no script, no outside file":
    let svg = renderSwimlane(studio, SwimOptions(fields: true))
    check "<script" notin svg and "href" notin svg and "url(http" notin svg
    check "prefers-color-scheme:dark" in svg

suite "swimlane picture: arrows are the blocks' own edges":
  test "every arrow drawn is an edge a block declares, in both models, whatever the flags":
    for m in [desk, studio]:
      let declared = declaredArrows(m)
      for o in [SwimOptions(), SwimOptions(fields: true), SwimOptions(spacious: true, reads: true)]:
        for a in drawnArrows(renderSwimlane(m, o)):
          check a in declared

  test "with --reads, every declared edge is drawn once, and nothing else":
    for m in [desk, studio]:
      let drawn = drawnArrows(renderSwimlane(m, SwimOptions(reads: true)))
      check drawn.len == drawn.toHashSet.len
      check drawn.toHashSet == declaredArrows(m)

  test "by default the reads arrows are left out and the rest is drawn":
    for m in [desk, studio]:
      let drawn = drawnArrows(renderSwimlane(m))
      check drawn.allIt(it.kind != "reads")
      check drawn.toHashSet == declaredArrows(m).toSeq.filterIt(it.kind != "reads").toHashSet

  test "an arrow needs both ends in the picture, and an edge to the wrong kind of block is not drawn":
    let m = parseModel("command C | produces Nowhere,V | reads E\nevent E\nview V | consumes E\nscreen S | commands C,Nope\n")
    let a = drawnArrows(renderSwimlane(m, SwimOptions(reads: true)))
    check a.toHashSet == [("S", "C", "offers"), ("E", "V", "consumes")].toHashSet

  test "edges() is sorted and has no repeats":
    let all = edges(studio)
    check all.len > 100
    check all == all.sortedByIt((it.src, it.dst, it.kind))
    check all.deduplicate.len == all.len
    check edges(parseModel("command C | produces E,E\nevent E\n")).len == 1

suite "swimlane picture: display flags":
  test "names only by default: no fields, no refusal codes":
    let svg = renderSwimlane(desk)
    check "class=\"em-field" notin svg
    check "class=\"em-kind\"" notin svg
    check ">game:string<" notin svg and ">refuses" notin svg

  test "--fields shows each box's fields and a command's refusal codes":
    let svg = renderSwimlane(desk, SwimOptions(fields: true))
    check "<text class=\"em-field\" font-size=\"10\" x=\"8\"" in svg
    check ">game:string<" in svg and ">text:string<" in svg
    check ">refuses busy,badMessage<" in svg or ">refuses badMessage,busy<" in svg
    check ">COMMAND<" in svg and ">EVENT<" in svg and ">VIEW<" in svg
    check ">ChatPanel<" in svg
    check svg.viewBox.h > renderSwimlane(desk).viewBox.h

  test "--spacious spaces the boxes more and sets larger text":
    let (w1, h1) = renderSwimlane(desk).viewBox
    let (w2, h2) = renderSwimlane(desk, SwimOptions(spacious: true)).viewBox
    check w2 > w1 and h2 > h1
    check "font-size=\"14\"" in renderSwimlane(desk, SwimOptions(spacious: true))
    check "font-size=\"12\"" in renderSwimlane(desk)

  test "the flags combine: each one still changes the picture":
    let plain = renderSwimlane(studio)
    let both = renderSwimlane(studio, SwimOptions(fields: true, spacious: true))
    let outputs = [plain, renderSwimlane(studio, SwimOptions(fields: true)), renderSwimlane(studio, SwimOptions(spacious: true)), both,
                   renderSwimlane(studio, SwimOptions(reads: true))]
    check outputs.toHashSet.len == outputs.len
    check both.viewBox.w > renderSwimlane(studio, SwimOptions(fields: true)).viewBox.w
    check both.viewBox.h > renderSwimlane(studio, SwimOptions(spacious: true)).viewBox.h
    # the same boxes and arrows whatever is shown
    check drawnBoxes(both) == drawnBoxes(plain)
    check drawnArrows(both) == drawnArrows(plain)

  test "a long field line is cut with an ellipsis":
    let m = parseModel("event E " & "abcdefghij".repeat(4) & ":int\n")
    let svg = renderSwimlane(m, SwimOptions(fields: true))
    check "abcdefghijabcdefghijabcdefg…" in svg
    check "abcdefghij".repeat(4) notin svg.replace("<title>event E " & "abcdefghij".repeat(4) & ":int</title>", "")

  test "--reads draws the dashed arrows":
    check "class=\"em-edge em-reads\"" notin renderSwimlane(studio)
    check renderSwimlane(studio, SwimOptions(reads: true)).count("class=\"em-edge em-reads\"") ==
      declaredArrows(studio).toSeq.countIt(it.kind == "reads")

suite "swimlane page (pic --html)":
  let html = page(studio, SwimOptions(), "Event model: studiodesk")

  test "one self-contained page: nothing is loaded from the network":
    check html.startsWith("<!doctype html>")
    check html.strip.endsWith("</html>")
    for bad in ["<link", "<script src", "src=\"http", "href=\"http", "url(http", "@import", "<iframe", "fetch(", "XMLHttpRequest"]:
      check bad notin html
    # the one address in the page is the SVG namespace
    check html.count("http://") == html.count("xmlns=\"http://www.w3.org/2000/svg\"")
    check "https://" notin html
    check html.count("<script>") == 1

  test "it holds the four drawings, names or fields, compact or spacious":
    for key in ["c-n", "c-f", "s-n", "s-f"]:
      check "data-key=\"" & key & "\"" in html
    check html.count("<svg ") == 4
    check html.count("class=\"em-box em-command\"") == 4 * studio.blocks.countIt(it.kind == "command")
    # ids stay unique across the four drawings
    check html.count("id=\"v-c-n-arrow\"") == 1 and html.count("id=\"v-s-f-arrow\"") == 1

  test "the drawings in the page are the picture, with every arrow":
    check html.count("class=\"em-edge em-reads\"") == 4 * declaredArrows(studio).toSeq.countIt(it.kind == "reads")
    check html.count("data-kind=\"produces\"") == 4 * declaredArrows(studio).toSeq.countIt(it.kind == "produces")

  test "it has the switches, the zoom and the touch handling":
    for needle in ["id=\"seg-detail\"", "id=\"seg-density\"", "id=\"c-reads\"", "id=\"b-fit\"", "addEventListener('wheel'",
                   "addEventListener('pointerdown'", "pointermove", "touch-action:none", "pinch", "ResizeObserver", "(pointer:coarse)",
                   "min-height:44px", "name=\"viewport\""]:
      check needle in html

  test "its data is JSON for the blocks, the arrows and the stories":
    let start = html.find("const MODEL = ") + len("const MODEL = ")
    let data = parseJson(html[start ..< html.find(";\n", start)])
    check data["blocks"].len == studio.blocks.countIt(it.kind in drawnKinds)
    check data["edges"].len == edges(studio).len
    check data["slices"].len == studio.slices.len
    check data["blocks"]["Desk"]["kind"].getStr == "view"
    check data["init"]["fields"].getBool == false

  test "the options choose what shows first":
    let opened = page(studio, SwimOptions(fields: true, spacious: true, reads: true))
    let start = opened.find("const MODEL = ") + len("const MODEL = ")
    let init = parseJson(opened[start ..< opened.find(";\n", start)])["init"]
    check init["fields"].getBool and init["spacious"].getBool and init["reads"].getBool

  test "a title or a name with markup cannot break out of the page":
    let nasty = parseModel("event E</script><b> x:int\nslice s</script> : E</script><b>\n")
    let p = page(nasty, SwimOptions(), "a</title><script>x")
    check p.count("</script>") == 1
    check "<title>a&lt;/title&gt;&lt;script&gt;x</title>" in p

  test "the page is deterministic":
    check page(desk) == page(desk)
