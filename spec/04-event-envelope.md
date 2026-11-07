# 4. Event envelope and log format

## The envelope

Every stored event is an envelope of four fields:

| Field | Type | Meaning |
|---|---|---|
| `seq` | `int` | Position in the log, starting at 1, no gaps. Stamped by the shell when the event is appended. |
| `at` | `int` | Milliseconds since the epoch. Stamped by the shell when the event is appended: the same value for every event of one command. |
| `kind` | `string` | The event block's name. |
| `data` | object | The event's fields, as JSON (see [03-types.md](03-types.md)). |

A decision produces events without `seq` and `at`. The shell stamps them: the first event of a
command gets the log's next position, the following ones the positions after it.

## The log form

JSON lines, UTF-8. One event per line, ended by `\n`. Each line is one JSON object with the keys
in this order: `seq`, `at`, `kind`, `data`. No white space between tokens.

```
{"seq":1,"at":1700000001000,"kind":"MessageSent","data":{"game":"cat","text":"make the cat jump higher"}}
{"seq":2,"at":1700000001000,"kind":"TurnStarted","data":{"game":"cat","turn":1,"agent":"claude"}}
```

A reader MUST accept any key order and any white space; a writer MUST write the form above, so
that a log is the same bytes whichever kit wrote it.

## A torn last line

A crash in the middle of an append can leave the last line cut short. A reader:

- MUST skip the last line of the log if it is not a complete envelope, and MUST read the events
  before it;
- MUST treat an incomplete line anywhere else as an error.

"The last line" means the last non-empty line, with or without a final `\n`.

A writer that opens an existing log MUST first remove a torn tail (the text after the last `\n`,
when the log does not end in `\n`), so the next event starts on a fresh line. The Nim file store
does this in `openFileStore`.

## Draft notes

- `seq` equal to the previous plus one is not checked by the prototype's reader.
- The same log form is used by the SQLite store as rows (`seq`, `at`, `kind`, `data` as text);
  the row form is not part of this spec.
