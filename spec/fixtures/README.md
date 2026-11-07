# Conformance fixtures

Plain data files that any kit reads unchanged. A kit **conforms** to a part of the spec when its
own runner passes every fixture of that part. The Nim runner is
[`tests/tconform.nim`](../../tests/tconform.nim), run by `nimble test`; a runner for another
language needs only a JSON parser, the kit's model-file parser and the kit's desk app.

| Part of the spec | Files | Runner step |
|---|---|---|
| Model file ([02](../02-model-file.md)) | [`model/parse.jsonl`](model/parse.jsonl) and the desk model [`examples/desk/desk.em`](../../examples/desk/desk.em) | [Parsing](#model-parsing) |
| Model check ([10](../10-model-check.md)) | [`model/check.jsonl`](model/check.jsonl) | [Model check](#model-check) |
| Event envelope and log ([04](../04-event-envelope.md)) | [`log/cases.jsonl`](log/cases.jsonl) and the `log/*.jsonl` logs it names | [Log](#log) |
| Scenarios ([11](../11-scenarios.md)) | [`scenarios/pass.jsonl`](scenarios/pass.jsonl), [`scenarios/fail.jsonl`](scenarios/fail.jsonl) and the 20 desk scenarios [`examples/desk/scenarios.jsonl`](../../examples/desk/scenarios.jsonl) | [Scenarios](#scenarios) |

## Conventions

- Files are UTF-8 with `\n` line ends, byte for byte (`.gitattributes` keeps them so). A `.jsonl`
  manifest holds one JSON object per line; blank lines are ignored. A manifest file is meant for
  reading by a kit; a log fixture is a log, and keeps the exact bytes its case describes (some
  end without a newline on purpose).
- Every case has a `name`, a sentence saying what it shows, unique in its file.
- Paths in a case (`file`, `log`, `then.file`, `then.sameAs`) are relative to the directory of the
  manifest that holds the case.
- JSON values are compared as JSON: object key order does not matter, array order does.
- Cases that read model text give it as `file` (a path to a model file) or as `lines`, a list of
  strings that are the lines of the text, in order. A runner joins `lines` with `\n` and ends the
  text with a final `\n`; an empty list is the empty text.
- **Expected failures carry no error code.** (Stable codes are assigned in a later milestone:
  [10-model-check.md](../10-model-check.md).) A case that must fail says so with `fails` and says
  what the failure *concerns*, in neutral terms:
  - `{"kind": K, "name": N}`: the block of kind `K` named `N`. `K` is one of the eight kinds
    ([01-vocabulary.md](../01-vocabulary.md)); a slice is named by its title.
  - `{"line": N}`: the line of the input that is wrong, counted from 1.

  A runner passes such a case when the kit fails in the stated place. Error wording, and codes
  when they exist, are the kit's own and are not compared. A field named `note` is reserved for a
  human comment and is ignored.

## Model parsing

`model/parse.jsonl`. Each case has the model text (`file` or `lines`) and `then`:

| `then` field | Meaning |
|---|---|
| `blocks` | The block lines of the text, in file order, as `{"kind", "name", "fields": ["name:type", ...], "edges": [{"key", "values": [...]}, ...]}`. Fields, edges and values are as written: not sorted. Slice lines are not blocks. |
| `slices` | The slice lines, in file order, as `{"title", "steps": [...]}`. The title has the white space around it removed. |
| `canonical` | The canonical line of each block, in file order ([02-model-file.md](../02-model-file.md#canonical-line)). |
| `counts` | `{kind: n}`: how many blocks of each kind the text holds, with `slice` counting slice lines. |
| `fails` | `{"concerns": {"line": N}}`: parsing MUST fail, because of line `N` of the text (a runner joins `lines` as above, so `N` is the index in `lines` plus one). |

Each field present is compared; a field left out is not.

## Model check

`model/check.jsonl`. Each case is a model and the code it is checked against:

- `lines`: the model text, as above.
- `code`: the blocks the code declares, as **canonical lines**, in any order. Only code kinds
  (`record`, `event`, `command`, `view`, `query`, `processor`) appear. It is the registry a kit
  builds from its code, written down so that no language is needed to read it.
- `then`: one of
  - `{"ok": true, "lints": [concern, ...]}`: the check passes (no error). The lints it raises
    are exactly these concerns, no more, no fewer; an empty list means none.
  - `{"fails": [concern, ...]}`: the check fails, and the errors it reports are exactly one for
    each concern listed: all the differences together, none missing and none extra. `lints` MAY be
    added to a failing case and is then checked the same way.

A reported error or lint **concerns** a block when its message names the block. This is what
lets a kit word its messages as it likes while the fixtures still say what must be found: a
runner finds, for each listed concern, a different message that names that block (a slice, by
its title) and requires that there be no other messages.

The check's two inputs are the model and the code. A model file with two blocks of one name, and
the rules for declarations in code (`EC001` to `EC009`), are not model-and-code differences and
have no fixture here: they are tested in each kit in the way its language allows.

## Log

`log/cases.jsonl`. Each case names a `log`, a file in the log form
([04-event-envelope.md](../04-event-envelope.md)), and `then`:

| `then` field | Meaning |
|---|---|
| `count` | A reader of the file finds this many events. |
| `events` | The events found, in order, each `{"seq", "at", "kind", "data"}`. |
| `last` | The last event found. |
| `sameAs` | The events found are those of the other log named here. |
| `canonical` | `true`: every line of the file is in the form a writer writes, so a writer given the events found writes the lines back byte for byte. |
| `view` | Needs `"app": "desk"` in the case. Fold the events found, in order, into the views of the desk app (its initial state first); each listed field of each listed view MUST equal the value ([scenario `view`](../11-scenarios.md#fields)). |
| `fails` | `{"concerns": {"line": N}}`: reading MUST fail, because line `N` is an incomplete envelope that is not the last line. A reader that cannot say which line is wrong is not required to. |

A case with `append` is about a writer instead. `append` is one envelope. The writer opens the
log named by `log`, appends that event, and closes it; the file MUST then hold exactly the
bytes of the file named by `then.file`. The case with a torn tail shows that the writer
removes the torn tail first.

Logs:

| File | Holds |
|---|---|
| `valid-16.jsonl` | The 16 events the desk's script of ten commands stores (the script is in `tests/tdesk.nim`): 6 commands accepted, 4 refused. Written by the Nim kit in the form 04 requires. |
| `valid-16-plus-1.jsonl` | The same, and a 17th event. |
| `empty.jsonl` | No bytes. |
| `loose-form.jsonl` | Three events, with other key order and white space, and a blank line. |
| `torn-tail.jsonl` | `valid-16.jsonl` and a last line cut short, with no final newline. |
| `torn-tail-final-newline.jsonl` | The same, the cut-short line ended by a newline. |
| `torn-tail-blank-lines.jsonl` | The same, the cut-short line followed by blank lines. |
| `torn-tail-no-data.jsonl` | The last line is whole JSON but lacks the envelope's `data`. |
| `torn-only.jsonl` | One cut-short line and nothing else. |
| `torn-middle.jsonl` | An incomplete line as the 6th of 16 lines. |

## Scenarios

[`scenarios/pass.jsonl`](scenarios/pass.jsonl), [`scenarios/fail.jsonl`](scenarios/fail.jsonl) and
the desk's [`scenarios.jsonl`](../../examples/desk/scenarios.jsonl) hold scenarios in the format of
[11-scenarios.md](../11-scenarios.md), for the desk app (`examples/desk`):

- A runner MUST find every scenario in `pass.jsonl` and in the desk's `scenarios.jsonl` passing.
- A runner MUST find every scenario in `fail.jsonl` failing. Each is a well-formed scenario
  whose `then` is wrong for the desk's rules; the reason a runner gives is not compared. This
  checks that a runner can say no.

`pass.jsonl` covers each part of the format: events only, accepted with no events listed, exact
events and their order, key order, refusal by code, `unknownCommand`, views after the events
are folded, views unchanged by a refusal, partial views, initial views, lists compared whole,
and `now`. No desk command reads `now`, so that scenario shows only that the field is accepted.

## What is not here

Named in the design notes and not yet written: a state digest (outline item 12), a log read by
a second kit, an event with an added field read from an old log (item 13), a processor delivered
twice (item 8). Their features are not in the M0 spec, so they have no fixture.
