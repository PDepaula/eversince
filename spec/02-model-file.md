# 2. Model file

A plain text file, UTF-8, one block per line. It is what a person reviews in a diff, and what a
tool such as the picture reads. The conventional extension is `.em`. A real example:
[`examples/desk/desk.em`](../examples/desk/desk.em).

## Lines

```
# comment                                  (also allowed after a line's content)
kind Name field:type field:type | key a,b | key c
slice title : A -> B -> C
```

- Everything from the first `#` to the end of the line is a comment. A name, field, type or
  slice title therefore MUST NOT contain `#`.
- Blank lines and comments are free. Order of lines is free: a checker compares blocks, not text.
- A **block line** has segments separated by `|`. The first segment is `kind Name` followed by
  zero or more fields, all separated by white space. A field is `name:type` with no white space
  inside it (see [03-types.md](03-types.md)). Every later segment is an **edge**: a key, white
  space, then one or more values separated by commas.
- A **slice line** is `slice`, a title, a colon, and a path of block names joined by `->`. The
  title is everything up to the first `:` and MAY contain spaces. It MUST NOT contain `:`.
- A line that fits neither shape is a parse error (codes `EP001` to `EP003`,
  [10-model-check.md](10-model-check.md)).

## Kinds and their edge keys

| Kind | Fields | Edge keys |
|---|---|---|
| `record` | yes | none |
| `event` | yes | none |
| `command` | yes (its input) | `reads` (views), `produces` (events), `refuses` (codes) |
| `view` | yes (its state) | `consumes` (events) |
| `query` | yes (its input) | `reads` (views), `returns` (one type) |
| `processor` | none | `consumes` (events), `issues` (commands) |
| `screen` | none | `queries`, `commands` |
| `slice` | none | the path |

`record`, `event`, `command`, `view`, `query` and `processor` are the **code kinds**: each also
exists in code and the checker compares the two. `screen` and `slice` exist only in the model file.

## Canonical line

To compare a model-file block with the same block in code, both are written in one canonical form:

```
kind Name field:type ... | key v1,v2 | key v3
```

- Fields keep their declared order. The order of fields is part of the block.
- Edges appear in this fixed key order: `reads`, `consumes`, `produces`, `refuses`, `issues`,
  `returns`, `queries`, `commands`.
- Values inside an edge are sorted (byte order) and joined with `,` and no spaces.
- An edge with no values is left out.
- Segments are joined with ` | `, fields with a single space.

Two blocks are the same if their canonical lines are equal.

## Slice rules

A slice is checked as a path: every adjacent pair must be an edge the blocks declare. The only
pairs that exist, by the kinds of the two blocks:

| From, to | The edge exists when |
|---|---|
| screen, command | the command is in the screen's `commands` |
| processor, command | the command is in the processor's `issues` |
| command, event | the event is in the command's `produces` |
| event, view | the event is in the view's `consumes` |
| event, processor | the event is in the processor's `consumes` |
| view, query | the view is in the query's `reads` |
| view, command | the view is in the command's `reads` |
| query, screen | the query is in the screen's `queries` |

Any other pair of kinds is an error (`EM007`). A step naming a block that does not exist is an
error (`EM005`).

## Draft notes

- The prototype's parser does not reject an unknown kind or an unknown edge key: such a line is
  parsed and then ignored by the code comparison. A conforming checker SHOULD reject both; the
  stable code for that is not assigned yet.
- Splitting one model across several files (one per area) is not specified.
