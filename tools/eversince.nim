## The eversince command line: `catalog`, `check`, `pic`, `scenarios`, `size`.
##
##   nimble tool                                  # builds bin/eversince
##   bin/eversince --help
##   bin/eversince catalog examples/desk/desk.em
##   bin/eversince check examples/desk/desk.em --app examples/desk/desk.nim
##   bin/eversince pic examples/desk/desk.em desk.svg
##   bin/eversince scenarios examples/desk/scenarios.jsonl --app examples/desk/desk.nim --model examples/desk/desk.em
##
## `catalog`, `pic`, `size` and `check` without `--app` read only the model file. With `--app`
## the code is needed, and this program is not the app: it writes a three-line program that
## imports the app's file and runs the same commands (`eversince/cli.runWithApp`), builds it in
## the system's temporary directory with `nim`, and runs it. The exit code passes through.

import std/[os, osproc, strutils, sequtils, hashes]
import eversince/cli

const kitSrc = currentSourcePath().parentDir.parentDir / "src"   ## where `import eversince` comes from

proc appTypeIn(source, given: string): string =
  ## The app type: `--app-type`, else the first name given to `sealModel(Name, ...)`.
  if given.len > 0: return given
  let at = source.find("sealModel(")
  if at < 0: return ""
  var i = at + len("sealModel(")
  while i < source.len and source[i] in {' ', '\t'}: inc i
  while i < source.len and source[i] in IdentChars: result.add source[i]; inc i

proc optionValue(args: seq[string], flag: string): string =
  for i, a in args:
    if a == flag and i + 1 < args.len: return args[i + 1]
    if a.startsWith(flag & "="): return a[flag.len + 1 .. ^1]

proc compileErrors(output: string): string =
  ## The part of the compiler's output worth showing: the `Error:` lines and what follows each.
  var keep: seq[string]
  var inError = false
  for line in output.splitLines:
    if "Error: " in line:
      inError = true
      keep.add line[line.find("Error: ") + 7 .. ^1]
    elif inError and (line.startsWith(" ") or line.len == 0):
      if line.strip.len > 0: keep.add line
    else: inError = false
  if keep.len == 0: output.strip else: keep.join("\n")

proc withApp(args: seq[string]): int =
  ## `check` or `scenarios` with `--app`: build a program that has the app in it, run it.
  let appPath = args.optionValue("--app")
  let source =
    try: readFile(appPath)
    except IOError:
      stderr.writeLine "eversince: cannot read " & appPath
      return exitCannot
  let appType = appTypeIn(source, args.optionValue("--app-type"))
  if appType.len == 0:
    stderr.writeLine "eversince: no `sealModel(Name, ...)` call in " & appPath & "; pass --app-type <Name>"
    return exitCannot
  let nim = findExe("nim")
  if nim.len == 0:
    stderr.writeLine "eversince: `nim` is not on the PATH (needed to build the app for --app)"
    return exitCannot
  let absApp = absolutePath(appPath)
  let work = getTempDir() / ("eversince-driver-" & toHex(hash(absApp).int, 16))
  createDir(work)
  let driver = work / "driver.nim"
  writeFile(driver, "import eversince, eversince/cli\nimport \"" & absApp.changeFileExt("").replace("\\", "/") &
    "\"\nrunWithApp[" & appType & "](" & $appType[0].toLowerAscii & appType[1 .. ^1] & "Catalog)\n")
  # -f: the app's model file is read at compile time, which Nim does not see as a dependency
  let build = execCmdEx(quoteShell(nim) & " c -f --hints:off --warnings:off --verbosity:0 --path:" & quoteShell(kitSrc) &
    " --path:" & quoteShell(absApp.parentDir) & " --nimcache:" & quoteShell(work / "nimcache") &
    " -o:" & quoteShell(work / ("driver" & ExeExt)) & " " & quoteShell(driver), options = {poStdErrToStdOut})
  if build.exitCode != 0:
    let why = compileErrors(build.output)
    if args[0] == "check" and "does not match the code" in why:
      # sealModel stopped the build: the app's own model file and its code disagree
      echo "check: " & args[1 .. ^1].filterIt(not it.startsWith("--"))[0] & " against " & appPath
      echo "error: the build of " & appPath & " stopped because its model file does not match its code"
      for line in why.splitLines: echo "  " & line.strip(leading = false)
      echo "result: FAIL (build stopped by sealModel)"
      return exitFail
    stderr.writeLine "eversince: the app does not build (" & appPath & "):"
    stderr.writeLine why
    return exitCannot
  execCmd(quoteShell(work / ("driver" & ExeExt)) & " " & args.mapIt(quoteShell(it)).join(" "))

proc main(): int =
  let args = commandLineParams()
  if needsApp(args): return withApp(args)
  var s: Sink
  result = dispatch(args, s)
  s.flush

quit main()
