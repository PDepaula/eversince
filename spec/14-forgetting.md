# 14. Forgetting

A log is append-only, but an app may owe its users a way to forget: delete a conversation, drop
old lines, keep a secret out of the file. A store that serves such an app does three things the
append-only store of [04](04-event-envelope.md) does not: it **cleans** events before they are
written, it **caps** how much one stream may hold, and it **forgets** a stream on request.

Forgetting is the one operation that changes what a replay gives. Everything else on this page
follows from that.

## Streams

A **stream** is a set of events that are forgotten together, such as one chat's events. The store
is given a rule that names the stream of an event with a string, or no stream (the empty string).
The rule is the app's: Para Studio's would be a chat's key, the desk's is the `game` of the event.
An event with no stream is never forgotten and never trimmed.

The store does not store streams: the rule is applied to the events when they are needed, so a
log's form does not change and an old log needs nothing added.

## The operations

**Forget a stream.** The store removes every event of the stream. The log that remains is in the
same order, in the same form, and holds every other event as it was. Asking for a stream the log
does not hold changes nothing. The empty string names no stream and is an error. A store that
cannot forget MUST say so (fail), not ignore the request.

**Cap.** The store is given a number of bytes. The **size** of a stream is the sum, over its
events, of the length in bytes of the event's line in the log form ([04](04-event-envelope.md))
including the final `\n`. When the size of a stream is over the cap (when the store is opened and
after every append), the store drops the oldest events of that stream until the rest is no more
than three quarters of the cap, rounded down. The stream's newest event always stays, even if it
is over the cap alone. A stream within its cap is not touched. (Three quarters, not the cap itself,
so that a full stream is not rewritten on every append.)

**Clean.** The store is given a function from an event to the event to be stored. It can change
`data`. It MUST NOT change `seq`, `at` or `kind`, which belong to the log. It is applied to each
event as it is appended, before the line is written and before the size is counted, and not to
events that are read. The views of a running app saw the event before it was cleaned; only the
stored form, and so a replay, has the cleaned text.

## The placeholder

After forgetting, positions can have gaps: `seq` rises but is no longer without gaps. But if what
is removed is the log's last events, a replay would hand out their positions again, and anything
that remembers a position (a processor, a snapshot) would be wrong. So when the log's last
position would be lost, the store writes one **placeholder** event at that position:

```
{"seq":16,"at":1700000009000,"kind":"eversince.forgotten","data":{}}
```

with the `seq` and `at` of the last event that was removed. Its kind is not an identifier, so no
event block can have it; a view consumes no such event and ignores it, as it ignores any event it
has no handler for ([01](01-vocabulary.md)). A placeholder that is no longer the last position
(a later event was appended) is dropped at the next rewrite; it is never dropped otherwise. A
placeholder belongs to no stream.

## What a view may assume

- A replay folds the events that remain. A view of a stream that was forgotten has no trace of it.
- To make a running app agree with that, the app clears the views itself, with an event, before
  the store forgets (the desk's `ConversationCleared`). Forgetting does not run any view.
- A view MUST NOT rely on counting events of a stream that can be forgotten, for a number that
  must not repeat: after forgetting, the count can be lower. The desk's `lastTurn` is such a view.
- A view that is a list of lines, per stream, is unaffected by the other streams being forgotten.

## Crash safety

A forget or a trim replaces the log as a whole: the new log is written to a temporary file next to
the log, and moved over it. A crash leaves the old log or the new one, never a mix, and possibly
a temporary file, which the next open removes. A torn last line ([04](04-event-envelope.md#a-torn-last-line))
is not an event: it is gone from the new log. An incomplete line anywhere else stops the rewrite
with an error and leaves the log as it was.

The rewrite writes every line in the log form, so a log read in a looser form comes out
canonical. Forgetting removes the events from the log, not the bytes from the disk: the file
system's free space is not wiped, and a copy of the log kept elsewhere (a backup, a snapshot of
the views) is the app's to deal with.

## Fixtures

[`fixtures/forget/cases.jsonl`](fixtures/forget/cases.jsonl): cases of forgetting a stream and of
a cap. The clean hook is code, not data, and has no fixture. See [`fixtures/README.md`](fixtures/README.md).

## Draft notes

- The Nim store keeps everything in one file and rewrites it. A store with one file per stream
  would delete a stream by deleting its file; it MUST give the same log, in the same order, when read.
- The prototype's `Runtime.execute` folds the event as the app decided it, not as the clean hook
  returned it.
