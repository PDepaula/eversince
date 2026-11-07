## The colours of the pictures, in one place: the stories layout (`picture`) and the swimlane
## layout (`swimlane`) draw with the same palette, light and dark.

type
  Palette* = object
    bg*, ink*, dim*, rule*, lane*, edge*: string
    kinds*: seq[tuple[kind, fill, stroke: string]]   ## screen, command, event, view, query, processor, missing

proc palette*(dark: bool): Palette =
  ## Plain colours, no custom properties, so that every SVG renderer (not only browsers) draws them.
  if dark:
    Palette(bg: "#16191d", ink: "#e6e8eb", dim: "#9aa3ad", rule: "#323840", lane: "#1d2126", edge: "#8d96a1",
      kinds: @[("screen", "#4a3c14", "#d6ad3b"), ("command", "#17324f", "#5ea3ee"), ("event", "#4d2c17", "#f08d4c"),
               ("view", "#173b25", "#52c07c"), ("query", "#2e2650", "#a08aeb"), ("processor", "#2a2e34", "#8d96a1"),
               ("missing", "#4b1d1d", "#ef6b6b")])
  else:
    Palette(bg: "#fbfbf9", ink: "#1b1f24", dim: "#5b6470", rule: "#d5d8dc", lane: "#f1f2f0", edge: "#59626d",
      kinds: @[("screen", "#fff4d6", "#c79a1c"), ("command", "#dcebff", "#3b82d6"), ("event", "#ffe3d1", "#d9732b"),
               ("view", "#dff4e4", "#2f9e57"), ("query", "#e8e0fb", "#7a5ad1"), ("processor", "#e7e9ec", "#6b7480"),
               ("missing", "#fde0e0", "#c93b3b")])
