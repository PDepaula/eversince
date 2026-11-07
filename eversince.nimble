# Package
version       = "0.0.1"
author        = "Patrick De Paula"
description   = "An event-modelling kit for Nim: command, event, view, query and processor blocks, a model file the compiler checks, and a picture of it."
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.0"

task test, "Run the tests (the SQLite store test is skipped on Windows)":
  var tests = @["tmodel", "tdesk", "ttally", "tpicture", "tconform", "tdigest", "tforget", "terrors", "tneg", "tcli", "tcli_e2e"]
  when not defined(windows):
    tests.add "tsqlite"
  for t in tests:
    exec "nim c -r --hints:off --warnings:off tests/" & t & ".nim"

task tool, "Build the command line tool into bin/eversince (catalog, check, pic, scenarios, size)":
  exec "nim c --hints:off -o:bin/eversince tools/eversince.nim"

task demo, "Run the desk example's evidence run (scenarios, replay across stores, timings)":
  exec "nim c -r --hints:off -d:release examples/desk/demo.nim"
