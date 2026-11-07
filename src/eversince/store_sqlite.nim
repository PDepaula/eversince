## SQLite store, through twelve C functions of the system's SQLite library; no Nimble package.
## Not part of `import eversince`: import `eversince/store_sqlite` where it is wanted, so that
## apps without SQLite never try to load the library.

import std/json
import ./[types, store]

# SQLite through twelve C functions; no nimble dependency.
const sqliteLib =
  when defined(windows): "sqlite3.dll"
  elif defined(macosx): "libsqlite3.dylib"
  else: "libsqlite3.so(|.0)"

{.push dynlib: sqliteLib, cdecl, importc.}
proc sqlite3_open(filename: cstring, db: var pointer): cint
proc sqlite3_close(db: pointer): cint
proc sqlite3_exec(db: pointer, sql: cstring, cb, arg: pointer, err: ptr cstring): cint
proc sqlite3_prepare_v2(db: pointer, sql: cstring, n: cint, stmt: var pointer, tail: ptr cstring): cint
proc sqlite3_bind_int64(stmt: pointer, idx: cint, v: int64): cint
proc sqlite3_bind_text(stmt: pointer, idx: cint, v: cstring, n: cint, destructor: pointer): cint
proc sqlite3_step(stmt: pointer): cint
proc sqlite3_reset(stmt: pointer): cint
proc sqlite3_finalize(stmt: pointer): cint
proc sqlite3_column_int64(stmt: pointer, col: cint): int64
proc sqlite3_column_text(stmt: pointer, col: cint): cstring
proc sqlite3_errmsg(db: pointer): cstring
{.pop.}

type SqliteStore* = ref object of Store
  db, ins: pointer

proc exec(s: SqliteStore, sql: string) =
  if sqlite3_exec(s.db, sql.cstring, nil, nil, nil) != 0:
    raise newException(IOError, "sqlite: " & $sqlite3_errmsg(s.db))

proc openSqliteStore*(path: string, sync = false): SqliteStore =
  ## `sync` asks SQLite to reach the disk on every commit (synchronous=FULL); without it a commit
  ## survives a crash of the program, and a power cut can lose the last few.
  result = SqliteStore()
  if sqlite3_open(path.cstring, result.db) != 0: raise newException(IOError, "sqlite: cannot open " & path)
  result.exec "PRAGMA journal_mode=WAL; PRAGMA synchronous=" & (if sync: "FULL" else: "NORMAL") & ";"
  result.exec "CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY, at INTEGER NOT NULL, kind TEXT NOT NULL, data TEXT NOT NULL)"
  discard sqlite3_prepare_v2(result.db, "INSERT INTO events(seq, at, kind, data) VALUES(?,?,?,?)", -1, result.ins, nil)

method append*(s: SqliteStore, evs: openArray[Envelope]) =
  ## One transaction per command. `seq` is the primary key, so a second writer that decided
  ## against the same position fails here instead of forking the log.
  s.exec "BEGIN IMMEDIATE"
  for e in evs:
    let data = $e.data
    discard sqlite3_bind_int64(s.ins, 1, e.seq)
    discard sqlite3_bind_int64(s.ins, 2, e.at)
    discard sqlite3_bind_text(s.ins, 3, e.kind.cstring, -1, cast[pointer](-1))
    discard sqlite3_bind_text(s.ins, 4, data.cstring, -1, cast[pointer](-1))
    if sqlite3_step(s.ins) != 101:
      let msg = $sqlite3_errmsg(s.db)
      discard sqlite3_reset(s.ins)
      s.exec "ROLLBACK"
      raise newException(IOError, "sqlite append refused at seq " & $e.seq & ": " & msg)
    discard sqlite3_reset(s.ins)
  s.exec "COMMIT"

method load*(s: SqliteStore): seq[Envelope] =
  var st: pointer
  discard sqlite3_prepare_v2(s.db, "SELECT seq, at, kind, data FROM events ORDER BY seq", -1, st, nil)
  while sqlite3_step(st) == 100:
    result.add Envelope(seq: sqlite3_column_int64(st, 0), at: sqlite3_column_int64(st, 1),
                        kind: $sqlite3_column_text(st, 2), data: parseJson($sqlite3_column_text(st, 3)))
  discard sqlite3_finalize(st)

method close*(s: SqliteStore) =
  discard sqlite3_finalize(s.ins)
  discard sqlite3_close(s.db)
