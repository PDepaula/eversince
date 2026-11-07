# eversince

An event-modelling kit for Nim. You write an app as five kinds of block (**command, event,
view, query, processor**) and a short **model file** that lists them. The compiler checks the
code against the model file in both directions, so a large codebase written by many agents (or
people) stays readable from one page: what changes the app, what it remembers, what it shows.

Status: **milestone M0** (private). The prototype's code, tests and the Para Studio desk
example are in; the spec has a first draft; the command line and the picture are in (M1); error
polish is in too (M1). Memory and file stores only; no durable store yet. Python kit later, in its own repo.

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

## The command line

`nimble tool` builds `bin/eversince`. Every command has `--help`; none needs the app's code
except `--app`, which builds the app into a small program (a few seconds, needs `nim` on the PATH).

```
eversince catalog <model.em>                         the blocks and what each is, as a list to read
eversince check <model.em> [--app <app.nim>] [--strict]   the model check, optionally against the code
eversince pic <model.em> [<out.svg>]                 the picture
eversince scenarios <file.jsonl> --app <app.nim> [--model <model.em>] [--strict]
eversince size <model.em>                            the size line
```

**For an agent**, in the order of a change: `catalog` at the start of a session instead of opening
source files; `check ... --app` after editing the model and the code (it prints every difference, one
`error:` per block, with the line to write); `scenarios` before saying done.

```
$ bin/eversince check examples/desk/desk.em --app examples/desk/desk.nim
check: examples/desk/desk.em against examples/desk/desk.nim
size: 8 commands, 9 events, 2 views, 2 query/queries, 2 processors, 2 screens, 6 slices
code: compared with the compiled blocks (27 blocks)
result: ok (0 errors, 0 warnings)

$ bin/eversince scenarios examples/desk/scenarios.jsonl --app examples/desk/desk.nim --model examples/desk/desk.em
scenarios: examples/desk/scenarios.jsonl (20 scenarios, checked against examples/desk/desk.em)
PASS   1  a message starts a turn
...
note: command EndStep has no accepted scenario
result: ok (20 passed, 0 failed, 5 uncovered)
```

`--model` makes `scenarios` also check each scenario against the model (its command, events and
refusal code exist) and note every command with no accepted scenario and every refusal code with
none. `--strict` turns lints (`check`) and those notes (`scenarios`) into failures.

**Exit codes** (the same for every command):

| Code | Meaning |
|---|---|
| 0 | ok (lints and notes are printed, they fail only under `--strict`) |
| 1 | the thing checked is wrong: model and code disagree, a scenario failed, a model file does not parse, or a lint under `--strict` |
| 2 | usage error: unknown command or option, missing or surplus argument |
| 3 | could not run: a file cannot be read or written, the app does not build, `nim` is missing |

`catalog` and `pic` print the same bytes for the same model file, whatever the order of its
lines (and nothing about the machine), so a diff of two outputs shows a change in the model. The
desk's outputs are kept in `tests/golden/` and the tests compare against them.

## The picture

`eversince pic examples/desk/desk.em desk.svg` draws the model file alone (no code): slices grouped
under the first screen they pass through, one band per slice, three lanes (who acts, requests and
answers, facts), steps left to right. Every box holds its block's line as a tooltip; a slice longer
than 10 steps continues on a second row; the SVG carries its own colours (light and dark).

## Build and test

Needs Nim 2.2 or newer.

```
nimble test      # model, desk, tally, picture, conformance, must-fail build, command line and SQLite tests (no SQLite on Windows)
nimble demo      # the desk example's evidence run: scenarios, replay across stores, timings
nimble tool      # builds bin/eversince (catalog, check, pic, scenarios, size)
```

## Layout

| Path | What |
|---|---|
| `src/eversince.nim` | the public import |
| `src/eversince/` | `blocks` (macros, `sealModel`), `model` (model-file parser and checker), `runtime`, `store`, `store_file`, `store_sqlite`, `picture`, `catalog`, `cli`, `types` |
| `tools/eversince.nim` | command line: `catalog`, `check`, `pic`, `scenarios`, `size` |
| `spec/` | the language-neutral spec, first draft, and its fixtures |
| `examples/tally/` | the README example |
| `examples/desk/` | the Para Studio desk: 8 commands, 9 events, 2 views, 20 scenarios, and the evidence run |
| `tests/` | the test suite; `tests/golden/` holds the desk's catalogue and picture byte for byte |
| `docs/m0-evidence.md` | the commands and results that show the prototype carried over |

## Licence

MIT, see `LICENSE`.
