# M0 evidence: the prototype's results from a clean clone

The design scout's 549-line prototype was moved in as `src/eversince/`. These are the commands
that reproduce its evidence and what they printed on the day M0 was built (2026-11-06, Linux,
Nim 2.2.12, SQLite 3.54.0), from a fresh `git clone` of the branch.

## Tests

```
nimble test
```

23 checks in 5 files, all passing: `tmodel` (12: model parse and every kind of model-versus-code
difference), `tdesk` (5: the 20 desk scenarios, replay from the memory and file stores,
the log's line form, a torn last line), `ttally` (3: the README example), `tpicture` (1),
`tsqlite` (2: replay from SQLite, a duplicate position refused; not run on Windows).

## The evidence run

```
nim c -r -d:release examples/desk/demo.nim 20000
```

| Prototype claim | Result here |
|---|---|
| 20 of 20 scenarios pass | `20 passed, 0 failed` |
| Same state after replay from memory, JSON lines and SQLite | `all 6 hashes equal: true`, every hash `53aac55296edd566`, 16 events (6 commands accepted, 4 refused); the hash is the state digest of `spec/12-state-digest.md` (M0 printed a Nim-only hash, `C2ADF9049F862B58`) |
| A torn last line is skipped | `torn tail: 16 events read, same state: true` |
| Log line form | first line `{"seq":1,"at":1700000001000,"kind":"MessageSent","data":{"game":"cat","text":"make the cat jump higher"}}` |
| Size line | `size: 8 commands, 9 events, 2 views, 2 query/queries, 2 processors, 2 screens, 6 slices` |
| Kit overhead is about a microsecond per command | memory 20,000 turns (60,000 commands, 80,000 events): execute 37 ms |
| Reaching the disk is the cost | with sync on every command, 1,500 commands: file 9.5 s, SQLite 9.4 s |

Timings vary by machine; the counts and hashes do not.

## The eleven builds that must fail

Each is the desk example built with one deliberate mistake: `-d:negEmit`, `-d:negClock`,
`-d:negEnv`, `-d:negView`, `-d:negQuery`, `-d:negIssue` (lines in `examples/desk/desk.nim`), or an
edit to a copy of `desk.em` (a changed `produces`, an added block, a deleted block, a bogus slice,
and `-d:eversinceStrict` with a command removed from its screen). All eleven stop with the
errors listed in the design notes, and the unedited build passes. `tests/tneg.nim` runs all
eleven (plus the unedited build, with and without strict mode) and asserts each one fails with a
stable fragment of its error.

## Picture and compile time

- `nim c -o:bin/eversince tools/eversince.nim`, then
  `bin/eversince pic examples/desk/desk.em desk.svg` writes 12,378 bytes, as the prototype did.
- `nim check examples/desk/desk.nim` takes about 0.41 s. The 660-block synthetic build used for
  the compile-time budget was not moved in.

## Not reproduced

Windows and macOS (CI runs them), threads, and anything about a cheap model adding a slice.
