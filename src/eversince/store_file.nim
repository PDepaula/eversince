## Append-only JSON-lines store: one event per line, readable with `cat` and `grep`.

import std/[json, strutils, os]
import ./[types, store]

type FileStore* = ref object of Store
  path: string
  f: File
  sync*: bool ## fsync after every append

when not defined(windows):
  proc fsync(fd: cint): cint {.importc, header: "<unistd.h>".}

proc openFileStore*(path: string, sync = false): FileStore =
  ## A last line cut short by a crash is cut off, so the next append starts on a fresh line.
  if fileExists(path):
    let text = readFile(path)
    if text.len > 0 and text[^1] != '\n':
      writeFile(path, text[0 .. text.rfind('\n')])
  FileStore(path: path, f: open(path, fmAppend), sync: sync)

method append*(s: FileStore, evs: openArray[Envelope]) =
  var buf = ""
  for e in evs: buf.add e.toLine & "\n"
  s.f.write buf
  s.f.flushFile
  when not defined(windows):
    if s.sync: discard fsync(s.f.getFileHandle)

method load*(s: FileStore): seq[Envelope] =
  ## A last line cut short by a crash is not an event: it is skipped.
  let lines = readFile(s.path).split('\n')
  var last = lines.high ## the last non-empty line: only that one may be torn
  while last > 0 and lines[last].strip.len == 0: dec last
  for i, line in lines:
    if line.strip.len == 0: continue
    try: result.add fromLine(line)
    except CatchableError:
      if i == last: break
      raise

method close*(s: FileStore) = s.f.close
