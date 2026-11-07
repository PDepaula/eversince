# eversince spec (first draft)

A language-neutral description of the event model eversince builds on. The Nim kit in `src/` is
the first implementation; a kit in another language conforms if it follows this spec and passes
the fixtures in [`fixtures/`](fixtures/README.md).

Status: **draft, written against the M0 prototype.** Where the prototype does something the spec
would not choose, the document says so under "Draft notes" instead of hiding it.

| File | Spec outline item | What it fixes |
|---|---|---|
| [01-vocabulary.md](01-vocabulary.md) | 1 | The eight kinds of block and what each may and may not do |
| [02-model-file.md](02-model-file.md) | 2 | The line grammar of the model file, edge keys per kind, slice rules |
| [03-types.md](03-types.md) | 3 | Type names and how they appear as JSON |
| [04-event-envelope.md](04-event-envelope.md) | 4 | The event envelope and the one-event-per-line log |
| [05-command-handling.md](05-command-handling.md) | 5 | What happens between a command arriving and the views being current |
| [06-processors.md](06-processors.md) | 6 | Processor positions, at-least-once delivery, restart |
| [10-model-check.md](10-model-check.md) | 10 | Every error and lint the model check reports, each with a stable code |
| [11-scenarios.md](11-scenarios.md) | 11 | The scenario fixture format |
| [12-state-digest.md](12-state-digest.md) | 12 | The state digest: canonical JSON of the views and its 64-bit hash |
| [13-tolerant-decoding.md](13-tolerant-decoding.md) | 13 | Decoding a stored event: defaults for missing fields, unknown keys ignored, wrong types refused |
| [14-forgetting.md](14-forgetting.md) | 14 | Streams, the cap, forgetting a stream, the placeholder, what a view may assume |
| [15-picture.md](15-picture.md) | 15 | The picture of a model: swimlane lanes, time order, arrows, display options |

Not written yet (outline items 6, 7 and 9): views and queries as separate
chapters, the store contract. The first draft covers only what the
prototype exercises. Their intended direction is recorded in the
project's design notes, not here.

Words used in these files: **MUST** and **MUST NOT** mark what a conforming kit has to do;
everything else is explanation.
