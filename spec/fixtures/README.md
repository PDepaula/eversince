# Fixtures

Files a kit reads to show it conforms. They live with the example they come from, not here, so
there is one copy of each.

| # | Fixture | Files | What it proves |
|---|---|---|---|
| 1 | The desk model file | [`examples/desk/desk.em`](../../examples/desk/desk.em) | A kit parses the same model: 8 commands, 9 events, 2 views, 2 queries, 2 processors, 2 screens, 6 slices |
| 2 | The 20 desk scenarios | [`examples/desk/scenarios.jsonl`](../../examples/desk/scenarios.jsonl) | Same decisions, same refusals, same view state ([11-scenarios.md](../11-scenarios.md)) |

The Nim kit passes both: `tests/tmodel.nim` (fixture 1) and `tests/tdesk.nim` (fixture 2), run by
`nimble test`.

Named in the design notes and not written yet: a 16-event log and its expected state, the same
log with a half-written last line, model-and-code pairs that must fail with their error codes,
a log written by one kit and read by another, an event with an added field read from an old log,
a processor delivered twice.
