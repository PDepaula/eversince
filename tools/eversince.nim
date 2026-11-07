## eversince command line. M0 ships `size` and `pic`; `catalog`, `check` and `scenarios` are M1.
##
##   nim c -o:bin/eversince tools/eversince.nim
##   bin/eversince size examples/desk/desk.em
##   bin/eversince pic examples/desk/desk.em desk.svg

import std/os
import eversince/[model, picture]

const usage = """usage: eversince <command> [args]
  size <model.em>             print the size line (counts of each block kind)
  pic <model.em> <out.svg>    draw the model file as an SVG, one band per slice
  catalog, check, scenarios   not built yet (milestone M1)"""

proc main(): int =
  let args = commandLineParams()
  if args.len == 0:
    echo usage
    return 1
  case args[0]
  of "size":
    if args.len != 2:
      echo usage
      return 1
    echo "size: " & parseModel(readFile(args[1])).counts
  of "pic":
    if args.len != 3:
      echo usage
      return 1
    let m = parseModel(readFile(args[1]))
    let svg = render(m)
    writeFile(args[2], svg)
    echo "wrote " & args[2] & " (" & $svg.len & " bytes) for " & m.counts
  of "catalog", "check", "scenarios":
    stderr.writeLine "eversince " & args[0] & " is not built yet (milestone M1)"
    return 2
  of "help", "-h", "--help":
    echo usage
  else:
    stderr.writeLine "unknown command: " & args[0] & "\n" & usage
    return 1

quit main()
