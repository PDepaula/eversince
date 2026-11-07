# 13. Tolerant decoding

An event is stored once and read for as long as the log lives. An app changes: a field is added
to an event, an old field is dropped. The events already stored keep the shape they had when they
were written, and every replay reads them again. A kit therefore decodes a stored event
**tolerantly**: an event written before a field existed is read, not refused.

This chapter fixes the decoding of a stored event's `data` ([04](04-event-envelope.md)) into the
event's type. It adds defaults for missing fields and nothing else: there is no version number
on an event and no rewriting of old events (an event's *meaning* changing is the app's to handle,
with a new event).

## The rules

A kit decodes the `data` of a stored event, given the event's type from the model
([02](02-model-file.md)), by these rules:

1. **A missing field takes its default.** A field of the type that has no key in `data` takes the
   default of its type, from the table below. The event is read as if the field had been stored
   with that value.
2. **An unknown key is ignored.** A key of `data` that is not a field of the type is not an error
   and is not kept.
3. **A field of the wrong JSON type is an error.** A key that is present must hold what its type
   says ([03](03-types.md)): a string for `string`, a number with no fraction for `int`, a
   number for `float`, `true` or `false` for `bool`, an array for `list[T]`, an object for a
   record. A value of another kind, and `null` for a type that is not `optional`, MUST fail the
   decoding. A kit MUST NOT turn the value into the type (`"3"` is not an `int`) and MUST NOT
   replace it with the default.
4. **`data` that is not an object is an error**, for the same reason.
5. **The rules apply all the way down.** A record inside the event, and each element of a list, is
   decoded by the same rules, so a record that gained a field is tolerated too.

### Defaults

| Type | Default |
|---|---|
| `string` | the empty string |
| `int` | `0` |
| `float` | `0.0` |
| `bool` | `false` |
| `list[T]` | the empty list |
| `optional[T]` | nothing (`null`) |
| a record | the record with every field at its default |

These are the same values a view has before any event is folded ([11](11-scenarios.md#steps-a-runner-follows),
step 1). A default is part of the type, not of the field: a model line cannot give a field a
default of its own (see the draft notes).

## The error

A decoding that fails (rules 3 and 4) MUST be an error that is raised to whoever asked for the
decoding, loudly, never skipped: a replay stops, a processor is not given the event and its
position does not move ([06](06-processors.md#delivery)), a scenario fails. The message MUST name:

- the **event**: the kind of the envelope;
- the **field**: the path to the field that is wrong (`turn`, `lines[2].who`), or, for rule 4,
  that the data itself is wrong;
- the **position**: the `seq` of the event in the log.

The words of the message are the kit's own. The Nim kit writes
`event TurnStarted at position 2, field turn: expected int, found string`.

## Where it applies

Everywhere a kit turns a stored event into a typed event: each view's handler, each processor's
handler, replay, and the scenario runner when it folds the `given` events. They share one
decoding, so the rules cannot differ between them. Reading the log itself ([04](04-event-envelope.md))
decodes only the envelope, and a missing key of the envelope is still an error there.

Commands are not stored, so they are not decoded by these rules.

## Fixtures

[`fixtures/decode/cases.jsonl`](fixtures/decode/cases.jsonl): old-shaped logs read with a default,
extra keys ignored, a wrong type and a payload that is not an object refused. Scenarios for the
same rules are in [`fixtures/scenarios/`](fixtures/scenarios/). See
[`fixtures/README.md`](fixtures/README.md#tolerant-decoding).

## Draft notes

- Deliberately not here: a per-field default written in the model line (the smallest change is
  that a default is the type's), a version number on an event, upcasting an old event to a new
  one. A later chapter can add them; a log written under these rules stays readable under them.
- The Nim kit applies the rules to events and to the records they hold. A field of a type it has
  no rule for (`Option`, `Table`, an enum) is decoded by `std/json`'s `to`, which is strict: a
  missing key there is an error. The prototype's model file does not map such types
  ([03](03-types.md)).
- Nim decodes a number given as `3.0` for an `int` field as a wrong type, as `to` always did.
