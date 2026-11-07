## The command line as a program: build tools/eversince.nim, run it, read its exit code and output.
## These are the cases that need a second build (`--app` builds the app into a small program), so
## they are few; `tcli` covers every other path in process.
import std/[unittest, os, osproc, strutils]

let root = currentSourcePath().parentDir.parentDir
let work = getTempDir() / "eversince-tcli-e2e"
let exe = work / ("eversince" & ExeExt)
let desk = root / "examples" / "desk"

proc run(args: string): tuple[output: string, code: int] =
  ## Runs the tool from the repository root, so paths in the output are the relative ones typed.
  let r = execCmdEx(quoteShell(exe) & " " & args, workingDir = root)
  (r.output.replace("\r\n", "\n"), r.exitCode)

suite "eversince program":
  setup:
    createDir(work)
  teardown:
    discard

  test "the tool builds":
    let r = execCmdEx(quoteShell(findExe("nim")) & " c --hints:off --warnings:off -o:" & quoteShell(exe) &
      " " & quoteShell(root / "tools" / "eversince.nim"), workingDir = root)
    check r.exitCode == 0

  test "catalog and size need only the model file":
    let c = run("catalog examples/desk/desk.em")
    check c.code == 0
    check c.output.startsWith("# eversince catalog\nsize: 8 commands")
    check run("size examples/desk/desk.em").output == "size: 8 commands, 9 events, 2 views, 2 query/queries, 2 processors, 2 screens, 6 slices\n"

  test "catalog is the same bytes on every run":
    check run("catalog examples/desk/desk.em").output == run("catalog examples/desk/desk.em").output

  test "check --app builds the app and compares: ok for the desk":
    let r = run("check examples/desk/desk.em --app examples/desk/desk.nim")
    check r.code == 0
    check "compared with the compiled blocks (27 blocks)" in r.output
    check "result: ok" in r.output

  test "check --app reports a model that disagrees with the code, exit 1":
    createDir(work / "drift")
    writeFile(work / "drift" / "desk.em", readFile(desk / "desk.em").replace("refuses staleStep", "refuses staleStep,gone"))
    let r = run("check " & quoteShell(work / "drift" / "desk.em") & " --app examples/desk/desk.nim")
    check r.code == 1
    check "model and code disagree about `command EndStep`" in r.output
    check "result: FAIL" in r.output

  test "check --app reports an app whose own model file does not match, exit 1":
    createDir(work / "tally")
    copyFile(root / "examples" / "tally" / "tally.nim", work / "tally" / "tally.nim")
    writeFile(work / "tally" / "tally.em", readFile(root / "examples" / "tally" / "tally.em").replace("refuses notPositive,tooMany", "refuses notPositive"))
    let r = run("check " & quoteShell(work / "tally" / "tally.em") & " --app " & quoteShell(work / "tally" / "tally.nim"))
    check r.code == 1
    check "model and code disagree about `command Count`" in r.output
    check "result: FAIL (build stopped by sealModel)" in r.output

  test "scenarios --app runs the desk scenarios, exit 0":
    let r = run("scenarios examples/desk/scenarios.jsonl --app examples/desk/desk.nim --model examples/desk/desk.em")
    check r.code == 0
    check r.output.count("PASS ") == 20
    check "result: ok (20 passed, 0 failed, 5 uncovered)" in r.output

  test "scenarios --app exits 1 when a scenario fails":
    writeFile(work / "s.jsonl", """{"name":"wrong","given":[],"when":{"command":"StopTurn","data":{"game":"x"}},"then":{"events":[]}}""" & "\n")
    let r = run("scenarios " & quoteShell(work / "s.jsonl") & " --app examples/desk/desk.nim")
    check r.code == 1
    check "FAIL   1  wrong" in r.output

  test "--app with a file that is missing, or has no sealModel, is exit 3":
    check run("check examples/desk/desk.em --app nope.nim").code == 3
    writeFile(work / "plain.nim", "echo 1\n")
    let r = run("check examples/desk/desk.em --app " & quoteShell(work / "plain.nim"))
    check r.code == 3
    check "sealModel" in r.output

  test "usage errors are exit 2":
    check run("").code == 2
    check run("scenarios examples/desk/scenarios.jsonl").code == 2
    check run("catalog --nope").code == 2

  test "pic to stdout is the picture the library draws":
    let r = run("pic examples/desk/desk.em -")
    check r.code == 0
    check r.output == readFile(root / "tests" / "golden" / "desk.svg").replace("\r\n", "\n")
