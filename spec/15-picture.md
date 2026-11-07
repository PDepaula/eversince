# 15. The picture

`eversince pic` draws a model file as an SVG, from the file alone (no code). This chapter fixes what
the default picture, the **swimlane timeline**, shows, so that a tool in another kit can draw the
same one. The tool's exact pixel positions are not part of the contract; the lanes, the order, the
arrows and the options are.

## What is drawn

One box for each block of kind `screen`, `processor`, `command`, `event`, `view` or `query`, drawn
once. `record` blocks, blocks of an unknown kind, and slice steps that name no block are not drawn.
When two lines declare the same name, the first one counts.

Lanes, top to bottom:

| Lane | Holds |
|---|---|
| who acts | screens and processors |
| commands | commands |
| events | events |
| views | views |
| queries | queries |

A lane with no blocks is left out.

## Time

Time runs left to right. The events fix it: they are placed in the order the slices first mention
them, slice by slice, step by step. Events no slice mentions come after those, sorted by name. Every
other block sits near the events it is joined to (the middle of them), and boxes of one lane that
would touch are pushed apart. Ties are broken by name, so **the order of the block lines in the file
never changes the picture**; the order of the slice lines does.

## Arrows

An arrow is an edge a block declares, and there are no others (slices are not drawn):

| Arrow | Declared by |
|---|---|
| command to event | the command's `produces` |
| event to view, event to processor | the view's or processor's `consumes` |
| processor to command | the processor's `issues` |
| screen to command | the screen's `commands` |
| query to screen | the screen's `queries` |
| view to command, view to query | the command's or query's `reads` |

An edge naming a block that is not drawn, or a block of the wrong kind, gives no arrow. The same
edge declared twice gives one. The view-to-reader arrows (`reads`) are drawn only when asked for,
because every command reads the same few views.

## Display options

| Option | Effect |
|---|---|
| `--fields` | a box also shows its kind, its fields (`name:type`, cut after 28 characters) and, for a command, its refusal codes |
| `--spacious` | wider gaps between boxes and between lanes, larger text |
| `--reads` | draws the `reads` arrows, dashed |

Options change the size and what is written in the boxes, never which blocks or arrows are drawn
(except `--reads`). They combine.

## The SVG

Plain SVG, deterministic: no clock, no randomness and no floating point, so the same model gives the
same bytes on every machine. It carries its own style, light and dark (`prefers-color-scheme`). Each
box is `<g class="em-box em-<kind>" data-name="Name">` holding the block's canonical line (spec 2) in
a `<title>`; each arrow is `<path class="em-edge em-<kind>" data-from data-to data-kind>`, so a tool
can read the picture back.

## The page

`--html` writes one HTML file that loads nothing from the network: the four drawings (names or
fields, compact or spacious), the style and the script are in it. It offers switches for the detail,
the density and the `reads` arrows; wheel zoom, drag to pan, one-finger pan and two-finger pinch;
the whole picture fitted to the window when it opens; and a click or tap on a box, or on a story in
the list, lights up the arrows it touches and fades the rest. Its controls are at least 44 px high
on a touch screen.

## The stories layout

`--layout stories` keeps the earlier picture: slices grouped under the first screen they pass
through, one band per slice. It shows only the arrows inside stories and not blocks that no
slice mentions; the swimlane shows every block and every declared arrow.
