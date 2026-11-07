## Append-only JSON-lines store: one event per line, readable with `cat` and `grep`.
##
## A log can forget (`spec/14-forgetting.md`). Three options of `openFileStore` and one method:
##   `clean`            cleans each event before it is written (for example, secrets removed)
##   `streamOf`         names the stream an event belongs to, so that a stream can be forgotten
##   `maxStreamBytes`   a cap on the bytes one stream may hold; its oldest events are dropped
##   `forget(stream)`   removes a whole stream
## Forgetting rewrites the file through a temporary file and a rename, so a crash leaves either
## the old log or the new one.

import std/[json, strutils, os, tables]
import ./[types, store]

type
  CleanProc* = proc (e: Envelope): Envelope {.closure.}
    ## Returns the event as it is to be stored. It may change `data`; `seq`, `at` and `kind` are
    ## the log's own and must stay as they are.
  FileStore* = ref object of Store
    path: string
    f: File
    sync*: bool ## fsync after every append
    clean: CleanProc
    streamOf: StreamOf
    maxStreamBytes: int
    sizes: Table[string, int] ## bytes of each stream's lines, kept while there is a cap

when not defined(windows):
  proc fsync(fd: cint): cint {.importc, header: "<unistd.h>".}

proc parseLog(text: string): seq[Envelope] =
  ## A last line cut short by a crash is not an event: it is skipped. An incomplete line anywhere
  ## else is an error.
  let lines = text.split('\n')
  var last = lines.high ## the last non-empty line: only that one may be torn
  while last > 0 and lines[last].strip.len == 0: dec last
  for i, line in lines:
    if line.strip.len == 0: continue
    try: result.add fromLine(line)
    except CatchableError:
      if i == last: break
      raise

proc readLog(s: FileStore): seq[Envelope] = parseLog(readFile(s.path))

proc lineBytes(e: Envelope): int = e.toLine.len + 1

proc measure(s: FileStore, log: seq[Envelope]) =
  s.sizes.clear
  for e in log:
    let st = streamOfEvent(s.streamOf, e)
    if st.len > 0: s.sizes[st] = s.sizes.getOrDefault(st) + e.lineBytes

proc rewrite(s: FileStore, log: seq[Envelope], keep: seq[bool]) =
  ## Replaces the file by the events of `log` that `keep` flags (and a placeholder if the log's
  ## last position would be lost), through a temporary file, and reopens it for appending.
  let kept = withoutDropped(log, keep)
  var text = ""
  for e in kept: text.add e.toLine & "\n"
  let tmp = s.path & ".tmp"
  s.f.close
  try:
    let t = open(tmp, fmWrite)
    try:
      t.write text
      t.flushFile
      when not defined(windows):
        if s.sync: discard fsync(t.getFileHandle)
    finally: t.close
    moveFile(tmp, s.path)
  finally:
    s.f = open(s.path, fmAppend)
  if s.maxStreamBytes > 0: s.measure kept

proc trim(s: FileStore) =
  ## Every stream over its cap loses its oldest events until it holds at most three quarters of the
  ## cap (so that the file is not rewritten on every append), but never its newest event.
  let log = s.readLog
  let target = s.maxStreamBytes * 3 div 4
  var kept: Table[string, int] ## bytes kept so far of each stream, newest first
  var full: seq[string] ## streams whose older events are all dropped
  var keep = newSeq[bool](log.len)
  for i in countdown(log.high, 0):
    let st = streamOfEvent(s.streamOf, log[i])
    if st.len == 0 or s.sizes.getOrDefault(st) <= s.maxStreamBytes:
      keep[i] = true
      continue
    let n = log[i].lineBytes
    if st notin full and (st notin kept or kept[st] + n <= target):
      keep[i] = true
      kept[st] = kept.getOrDefault(st) + n
    else:
      full.add st
  s.rewrite(log, keep)

proc openFileStore*(path: string, sync = false, clean: CleanProc = nil,
                    streamOf: StreamOf = nil, maxStreamBytes = 0): FileStore =
  ## A last line cut short by a crash is cut off, so the next append starts on a fresh line. A
  ## temporary file a crashed rewrite left behind is removed. `maxStreamBytes` (0: no cap) needs
  ## `streamOf`; a log already over the cap is trimmed now.
  if maxStreamBytes > 0 and streamOf.isNil:
    raise newException(ValueError, "openFileStore: maxStreamBytes needs streamOf")
  removeFile(path & ".tmp")
  if fileExists(path):
    let text = readFile(path)
    if text.len > 0 and text[^1] != '\n':
      writeFile(path, text[0 .. text.rfind('\n')])
  result = FileStore(path: path, f: open(path, fmAppend), sync: sync, clean: clean,
                     streamOf: streamOf, maxStreamBytes: maxStreamBytes)
  if maxStreamBytes > 0:
    result.measure result.readLog
    for n in result.sizes.values:
      if n > maxStreamBytes:
        result.trim
        break

proc cleaned(s: FileStore, e: Envelope): Envelope =
  if s.clean.isNil: return e
  result = s.clean(e)
  if result.seq != e.seq or result.at != e.at or result.kind != e.kind or result.data.isNil:
    raise newException(ValueError, "the clean hook may change an event's data, not its seq, at or kind")

method append*(s: FileStore, evs: openArray[Envelope]) =
  var buf = ""
  var added = initTable[string, int]()
  for e in evs:
    let c = s.cleaned(e)
    let line = c.toLine & "\n"
    buf.add line
    if s.maxStreamBytes > 0:
      let st = streamOfEvent(s.streamOf, c)
      if st.len > 0: added[st] = added.getOrDefault(st) + line.len
  s.f.write buf
  var over = false
  for st, n in added:
    s.sizes[st] = s.sizes.getOrDefault(st) + n
    if s.sizes[st] > s.maxStreamBytes: over = true
  s.f.flushFile
  when not defined(windows):
    if s.sync: discard fsync(s.f.getFileHandle)
  if over: s.trim

method load*(s: FileStore): seq[Envelope] = s.readLog

method forget*(s: FileStore, stream: string) =
  ## Removes every event of `stream`. The views of a running app are not touched: the app clears
  ## them itself (with an event) before it forgets. The file's free space is not wiped.
  if s.streamOf.isNil: raise newException(CatchableError, "this store has no streams: pass streamOf to openFileStore")
  if stream.len == 0: raise newException(ValueError, "forget: the empty string names no stream")
  let log = s.readLog
  var keep: seq[bool]
  for e in log: keep.add streamOfEvent(s.streamOf, e) != stream
  if false in keep: s.rewrite(log, keep)

method close*(s: FileStore) = s.f.close
