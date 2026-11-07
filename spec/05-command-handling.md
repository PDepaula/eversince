# 5. Command handling

How the runtime handles one command. A kit MAY structure its code any way it likes as long as an
observer sees the steps in this order.

## Inputs and output

A command is handled from:

- the command's **name** and **data** (a JSON object of the command's fields);
- the **views** the command declares under `reads`, already up to date;
- the **context**: `now` (milliseconds, handed in by the shell) and `nextSeq` (the next log
  position). A decision MUST learn the time and the position from the context only.

The result is exactly one of:

- a list of events, each of a kind in the command's `produces` list (possibly empty);
- a **refusal**: a `code` from the command's `refuses` list and a human-readable `message`.

An unknown command name is refused with the code `unknownCommand` and the name as the message.

## Steps

1. **Decide.** Run the command's decision on the inputs above. It is pure
   ([01-vocabulary.md](01-vocabulary.md)). If it refuses, stop: nothing is stored, no view
   changes, no processor runs, and the refusal is the answer.
2. **Stamp.** Give each event its `seq` and `at` ([04-event-envelope.md](04-event-envelope.md)).
3. **Append.** Add all events to the store as one atomic unit: all of them or none. A store
   that cannot do this MUST NOT be used with this spec.
4. **Fold.** Apply each event, in order, to every view that consumes its kind. Views are
   current before the command returns, so the next command reads up-to-date views.
5. **React.** Give each event, in order, to every processor that consumes its kind. A processor
   MAY have side effects. The commands it issues are collected, and when every event has been
   given to every processor, the collected commands are handled one after another, each by
   these same steps, in the order they were issued. A refusal of an issued command is not an
   error of the original command. Each processor remembers how far it has got:
   [06-processors.md](06-processors.md).

Only one command is handled at a time. A command that arrives while another is being handled
waits for it.

## Replay

A view's state is a fold of the log. To rebuild it, apply every stored event, in order, to the
views that consume it. **Replay runs no decision and no processor again.** Processors' results
were stored as the events of the commands they issued.

## Delivery to processors

A processor MAY be given the same event more than once (after a restart, for instance), so the
commands it issues MUST be safe to repeat: a repeated command is refused, for example with a
`stale...` code, instead of being applied twice. The desk example shows the pattern with
`staleTurn` and `staleStep`. Positions and the rules of delivery are in
[06-processors.md](06-processors.md).

## Draft notes

- The prototype's store interface is `append`, `load` and `close`. Its append takes the events
  of one command together, which is the atomic unit above. Views are not written into the
  store.
