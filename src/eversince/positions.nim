## Where each processor remembers how far into the log it has got: a position is the `seq` of the
## last event the processor was given, and whose issued commands were handled. Kept apart from the
## event store, so the store interface stays as small as it is. `MemPositions` forgets on exit;
## `FilePositions` keeps one small JSON file, replaced whole and atomically on every save.

import std/[json, os, tables, algorithm]

type
  Positions* = ref object of RootObj
  MemPositions* = ref object of Positions
    at: Table[string, int64]
  FilePositions* = ref object of Positions
    path: string
    at: Table[string, int64]
    sync*: bool ## fsync the new file before it replaces the old one

method get*(p: Positions, processor: string): int64 {.base.} = 0
  ## 0 when nothing is remembered: the processor has been given no event yet.
method save*(p: Positions, updates: openArray[(string, int64)]) {.base.} = discard
  ## Remember several positions as one unit: all of them or none.
method close*(p: Positions) {.base.} = discard

method get*(p: MemPositions, processor: string): int64 = p.at.getOrDefault(processor)
method save*(p: MemPositions, updates: openArray[(string, int64)]) =
  for (name, pos) in updates: p.at[name] = pos

when not defined(windows):
  proc fsync(fd: cint): cint {.importc, header: "<unistd.h>".}

proc openFilePositions*(path: string, sync = false): FilePositions =
  ## A missing file is no positions. An unreadable one raises: starting every processor over
  ## would repeat their side effects, which is not for the kit to decide.
  result = FilePositions(path: path, sync: sync)
  if fileExists(path):
    try:
      for name, pos in parseFile(path): result.at[name] = pos.getBiggestInt
    except CatchableError as e:
      raise newException(IOError, "positions file " & path & " is not a JSON object of numbers: " & e.msg)

method get*(p: FilePositions, processor: string): int64 = p.at.getOrDefault(processor)

method save*(p: FilePositions, updates: openArray[(string, int64)]) =
  var next = p.at
  for (name, pos) in updates: next[name] = pos
  var text = "{"
  var names: seq[string]
  for name in next.keys: names.add name
  for i, name in names.sorted:
    if i > 0: text.add ","
    text.add escapeJson(name) & ":" & $next[name]
  text.add "}\n"
  let tmp = p.path & ".tmp"
  let f = open(tmp, fmWrite)
  try:
    f.write text
    f.flushFile
    when not defined(windows):
      if p.sync: discard fsync(f.getFileHandle)
  finally:
    f.close
  moveFile(tmp, p.path)
  p.at = next
