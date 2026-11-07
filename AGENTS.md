# Contributing to eversince

## Build and test

- Needs Nim 2.2 or newer. From the repository root: `nimble test` runs every test, `nimble demo`
  runs the desk example's evidence run, `nimble tool` builds `bin/eversince`.
- Compiled programs go to `bin/` (see `config.nims`); do not commit them.
- CI runs `nimble test` on Linux, macOS and Windows. The SQLite test needs the system's SQLite
  library and is skipped on Windows.

## The model-file rule

An app's behaviour is written as blocks in code (`event`, `command`, `view`, `query`,
`processor`, `record`) and listed in its model file (`.em`, see `spec/02-model-file.md`). They
must agree: `sealModel` stops the build when they do not.

1. Change the model file first: the new block's line, and the `slice` line that tells the story.
2. Build. The error lists the blocks the model has and the code lacks, with the line to write.
3. Write those blocks and nothing else. Then build again.
4. Only a `processor` may touch the clock, files, the network or a child process. A command's
   `decide`, a view's `on` handlers and a query's `answer` are pure; the compiler enforces it.
5. Every new command gets scenarios in the app's `scenarios.jsonl`: one accepted, one per refusal
   code (format: `spec/11-scenarios.md`).
