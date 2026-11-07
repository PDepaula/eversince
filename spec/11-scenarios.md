# 11. Scenario format

A scenario is a small, language-neutral test of one decision: given these past events, when this
command arrives, then these events or this refusal, and optionally what a view then holds. A kit
conforms to the command rules if it passes every scenario in the fixture files.

## File

UTF-8, JSON lines: one JSON object per line. Blank lines are ignored.

## Fields

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | A sentence saying what the scenario shows. Unique in its file. |
| `given` | yes | A list of past events `{"kind": ..., "data": {...}}`, oldest first. May be empty. |
| `when` | no | The command: `{"command": "Name", "data": {...}}`. |
| `now` | no | Milliseconds handed to the decision as `now`. Default `0`. |
| `then` | yes | What is expected, below. |

`then` holds one of:

- `"refused": "code"`: the command MUST be refused with exactly this code. The message is not
  compared.
- `"events": [{"kind": ..., "data": {...}}]`: the command MUST be accepted and MUST produce
  exactly these events, in this order. `seq` and `at` are not compared. If `events` is left out,
  the command only has to be accepted.

and, with either, optionally:

- `"view": {"ViewName": {"field": value, ...}}`: after the steps below, each listed field of that
  view's state MUST equal the value. Only the fields listed are compared. A list is compared
  whole, in order.

## Steps a runner follows

1. Start with every view in its initial state (an empty state: fields zero, empty or false).
2. Apply each `given` event, in order, to the views that consume its kind. The events get
   `seq` 1, 2, 3 and so on.
3. If there is a `when`: run the command's decision with the views it reads and the context
   `now` and `nextSeq = number of given events + 1`.
   - If `then` has `refused`: fail unless the decision refused with that code.
   - Otherwise: fail if the decision refused; fail if `then.events` is present and the produced
     events differ; otherwise apply the produced events to the views.
4. If `then` has `view`: compare the listed fields.
5. A scenario passes when no step failed.

Comparison is by JSON value: object key order does not matter, array order does.
A runner runs decisions and folds only. It touches no store, no processor and no clock.

## Example

From [`examples/desk/scenarios.jsonl`](../examples/desk/scenarios.jsonl), one line, here
spread over several lines:

```json
{"name": "a step is refused while that game's turn runs",
 "given": [{"kind": "TurnStarted", "data": {"game": "cat", "turn": 1, "agent": "claude"}}],
 "when": {"command": "StartStep", "data": {"game": "cat", "kind": "check", "message": ""}},
 "then": {"refused": "busy"}}
```

and one that checks events and a view:

```json
{"name": "a new conversation clears only that game's lines",
 "given": [{"kind": "MessageSent", "data": {"game": "cat", "text": "a"}},
           {"kind": "MessageSent", "data": {"game": "dog", "text": "b"}}],
 "when": {"command": "NewConversation", "data": {"game": "cat"}},
 "then": {"events": [{"kind": "ConversationCleared", "data": {"game": "cat"}}],
          "view": {"Chat": {"lines": [{"game": "dog", "who": "you", "text": "b"}]}}}}
```

## Draft notes

- A scenario with `given` and `then.view` but no `when` checks only that folding the given events
  gives that state. The prototype runner supports it; no desk scenario uses it.
- The prototype runner returns an empty string for a pass and the reason for a failure. The
  reason text is not part of the spec.
- Fixtures for a replayed log, a torn tail, models that must fail and processors delivered twice
  are named in the design notes (fixtures 3 to 8) and are not written yet.
