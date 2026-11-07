# 1. Vocabulary

Eight kinds of block. Six exist in code. Two (screen, slice) exist only in the model file.

| Kind | What it is | Contract | In code |
|---|---|---|---|
| **event** | A recorded fact, named in the past tense | A name plus typed fields. MUST NOT change after it is stored. | yes |
| **command** | A request to change something | Reads views, then either emits events from its declared list or refuses with a code from its declared list. MUST have no side effects. | yes |
| **view** | What the app remembers | A fold: one handler per event it consumes. MUST have no side effects. | yes |
| **query** | A question a screen asks | Reads views, returns data, changes nothing. | yes |
| **processor** | Background work | Reacts to events. The only block allowed side effects. MAY issue only the commands it declares. | yes |
| **record** | A plain value type carried by the others | A name plus typed fields. | yes |
| **screen** | What a person or API touches | Lists the queries and commands it uses. | model file only |
| **slice** | One story, left to right | A path of blocks, for example screen, command, event, view, query, screen. Every step MUST be an edge the blocks declare. | model file only |

Rules that follow:

- A block name is unique across all kinds. Two blocks MUST NOT share a name.
- A command's `decide`, a view's fold handlers and a query's `answer` are **pure**: the same
  inputs give the same output, and they read no clock, file, network, environment or global
  random source. "Now" and the next log position are handed in (see
  [05-command-handling.md](05-command-handling.md)). A kit MUST enforce this where its language
  allows it, and MUST say where it cannot (a language without an effect system can only lint).
- A command MAY emit only the events in its `produces` list and MAY refuse only with codes in
  its `refuses` list. A processor MAY issue only the commands in its `issues` list.
- A view consumes exactly the events it has handlers for. An event a view does not consume is
  ignored by that view.

Left out on purpose: a separate clock or periodic-task block (a clock is a processor whose
trigger is time), tenants, a control plane, a behaviour-spec language.

## Draft notes

- In the Nim prototype a processor body may do anything, as its job requires; only the commands
  it issues are checked.
- Nothing checks that a declared event is actually emitted or a declared refusal actually used.
  Only that undeclared ones are not.
