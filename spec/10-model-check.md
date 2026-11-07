# 10. Model check

The check that stops a build, or fails a test, when the model file and the code disagree, and
that finds blocks connected to nothing. Each result has a **stable code**. A code is never
reused for another meaning.

Codes begin with `E` for an error and `L` for a lint, then a letter for the group, then a number:

- `EP`: the model file does not parse
- `EM`: model and code disagree, or the model is not true to itself
- `EC`: a declaration in code breaks a rule of the vocabulary
- `LI`: lint, a block that connects to nothing

A **lint** is a warning by default and an error under the strict switch.

## Model file does not parse

| Code | When |
|---|---|
| `EP001` | A `slice` line has no `:` (needs `slice title : A -> B`). |
| `EP002` | A block line has no kind and name. |
| `EP003` | An edge segment has no key, or no values. |

## Model and code disagree (code kinds only)

The comparison is by canonical line ([02-model-file.md](02-model-file.md)). Screens and slices
have no code, so they are checked for truth instead.

| Code | When | What the message gives |
|---|---|---|
| `EM001` | The model has a block the code lacks. | The model line, so it can be written in code or deleted. |
| `EM002` | The code has a block the model lacks. | The line to add to the model. |
| `EM003` | A block of one name is in both and the canonical lines differ. | Both lines, labelled model and code. |
| `EM004` | A screen names a query or command that does not exist. | Screen and name. |
| `EM005` | A slice names a block that does not exist. | Slice title and name. |
| `EM006` | A slice step is not an edge the blocks declare. | Slice title and the two names. |
| `EM007` | A slice step leads from one kind to a kind that no edge connects (for example a view to an event). | Slice title, both kinds and names. |

All differences are reported together, in one failure, not one at a time.

## Declarations in code

How a kit reports these depends on its language: a compile error in Nim, a failure at import in
a kit without a compiler. Each MUST stop the build or the start-up.

| Code | When |
|---|---|
| `EC001` | A command emits an event its `produces` list does not contain. |
| `EC002` | A processor issues a command its `issues` list does not contain. |
| `EC003` | Two blocks have the same name. |
| `EC004` | A view has two handlers for one event. |
| `EC005` | A decision, a fold handler or an answer has a side effect, or reads the clock, the environment or a global. A kit without an effect system MUST say how it approximates this (a lint over banned imports). |
| `EC006` | A query changes a view. |
| `EC007` | A command has no decision, or a query lacks `returns` or `answer`. |
| `EC008` | A declaration has a section the kind does not allow. |
| `EC009` | A command refuses with a code its `refuses` list does not contain. |

## Lints

| Code | When |
|---|---|
| `LI001` | An event is produced by no command. |
| `LI002` | An event is consumed by no view and no processor. |
| `LI003` | A view is read by no query and no command. |
| `LI004` | A command is on no screen and issued by no processor. |
| `LI005` | A query is on no screen. |

## Draft notes

- **The M0 prototype does not print these codes.** Its messages carry the text in the "what the
  message gives" column but no code. Adding the codes to the messages is milestone M1 work.
  The mapping from code to prototype message is by the "When" text above and
  `src/eversince/model.nim` (`checkModel`) and `src/eversince/blocks.nim` (the macros).
- `EC005` and `EC006` appear in the prototype as the Nim compiler's own errors (`'decide' can
  have side effects`, `... can have an unlisted effect: ReadEnvEffect`, `expression ... is
  immutable, not 'var'`), not as messages the kit writes.
- `EC009` is true of the prototype by construction (`refuse` accepts only the generated enum of
  the command's codes) and surfaces as a Nim type error.
- Two of the prototype's compile errors have no file name or line in the user's code
  (`EC001`, `EC002`); fixing that is M1.
- The strict switch is `-d:eversinceStrict` in the Nim kit. Its name in other kits is theirs to
  choose; the spec only requires that lints can be made errors.
