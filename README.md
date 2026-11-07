# eversince

An event-modelling kit for Nim. You write an app as five kinds of block (**command, event,
view, query, processor**) and a short **model file** that lists them. The compiler checks the
code against the model file in both directions, so a large codebase written by many agents (or
people) stays readable from one page: what changes the app, what it remembers, what it shows.

Status: **milestone M0** (private). The prototype's code, tests and the Para Studio desk
example are in; the spec has a first draft; the picture and error polish
are M1. Memory and file stores only; no durable store yet. Python kit later, in its own repo.

## Example

A counter that refuses to pass 100. `examples/tally/tally.nim`:

```nim
import std/os
import eversince

event Counted:
  by: int

view Tally:
  state:
    total: int
  on Counted:
    state.total += e.by

command Count:
  fields:
    by: int
  reads Tally
  produces Counted
  refuses notPositive, tooMany
  decide:
    if cmd.by <= 0: refuse notPositive, "Count at least one."
    if tally.total + cmd.by > 100: refuse tooMany, "The tally stops at 100."
    emit Counted(by: cmd.by)

query CurrentTotal:
  reads Tally
  returns int
  answer: tally.total

sealModel(TallyApp, currentSourcePath().parentDir / "tally.em")
```

`examples/tally/tally.em`, the model file a reviewer reads (one block per line):

```
# tally.em: the smallest complete model. Blocks are checked against tally.nim by the compiler.
screen Counter | queries CurrentTotal | commands Count
slice count up : Counter -> Count -> Counted -> Tally -> CurrentTotal -> Counter

command Count by:int | reads Tally | produces Counted | refuses notPositive,tooMany
event Counted by:int
view Tally total:int | consumes Counted
query CurrentTotal | reads Tally | returns int
```

Add a block to the code and not to the model file (or the other way round) and the build stops
with the line you have to write. Using it:

```nim
var rt = Runtime[TallyApp](store: MemStore(), clock: proc (): int64 = 1000)
discard rt.execute("Count", %*{"by": 3})          # refused == false
echo rt.app.answer("CurrentTotal", %*{})          # 3
```

## The picture

> **Placeholder.** The at-a-glance picture (one band per slice, three lanes) is milestone M1.
> The prototype's version already runs: `nimble tool` then
> `bin/eversince pic examples/desk/desk.em desk.svg`.

## Build and test

Needs Nim 2.2 or newer.

```
nimble test      # model, desk, tally, picture, conformance, must-fail build and SQLite tests (no SQLite on Windows)
nimble demo      # the desk example's evidence run: scenarios, replay across stores, timings
nimble tool      # builds bin/eversince (commands: size, pic)
```

## Layout

| Path | What |
|---|---|
| `src/eversince.nim` | the public import |
| `src/eversince/` | `blocks` (macros, `sealModel`), `model` (model-file parser and checker), `runtime`, `store`, `store_file`, `store_sqlite`, `picture`, `types` |
| `tools/eversince.nim` | command line: `size`, `pic` (`catalog`, `check`, `scenarios` are M1) |
| `spec/` | the language-neutral spec, first draft, and its fixtures |
| `examples/tally/` | the README example |
| `examples/desk/` | the Para Studio desk: 8 commands, 9 events, 2 views, 20 scenarios, and the evidence run |
| `tests/` | the test suite |
| `docs/m0-evidence.md` | the commands and results that show the prototype carried over |

## Licence

MIT, see `LICENSE`.
