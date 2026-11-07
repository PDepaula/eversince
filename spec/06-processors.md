# 6. Processors: positions and delivery

A processor ([01-vocabulary.md](01-vocabulary.md)) reacts to events and is the one block with side
effects. This chapter fixes how events reach it, what a restart does, and what a processor's
author must do so that a restart never applies anything twice.

## Position

Each processor has a **position**: the `seq` of the last event of the log that it was given and
whose issued commands were all handled. A processor that has none remembered has position `0`.

A kit remembers positions apart from the log. How is the kit's own choice, but a position MUST
survive a restart when the kit is told to keep them, and saving several positions MUST be one
atomic unit: all of them or none. Positions are not events, and replay never writes them.

## Delivery

After a command's events are appended and folded ([05-command-handling.md](05-command-handling.md)),
the kit **catches up** every processor:

1. Give each event with a `seq` greater than the processor's position, up to the head of the log,
   in log order, to every processor that consumes its kind. An event after the position is given
   even if earlier events are missing from the log: a position is a `seq`, not a count.
2. When every event of the round has been given to every processor, handle the commands they
   issued, one after another, in the order issued, each by the steps of chapter 5. Their events
   make the next round.
3. Only then move each processor's position to the head of the round. A processor's position
   moves for every event, whether or not it consumes the kind.
4. Repeat until a round appends nothing.

A processor that fails (its code raises) stays where it was, its position does not move, and the
failure goes to the caller of the command. Its events are given again at the next catch-up.

## At least once

A crash after step 2 and before step 3 gives the same events to the processor again after the
restart. So delivery is **at least once**, and two things follow, both for the author:

- **The commands a processor issues MUST be safe to repeat.** A repeated command is refused
  (`staleTurn`, `staleStep` in the desk), not applied twice. A kit cannot check this; the
  [processor fixtures](fixtures/README.md#processors) show it.
- **A processor's own side effect may happen twice** for one event. If that matters it must make
  the effect repeat-safe too (look before it acts).

## Restart

To restart, a kit rebuilds the views by replay ([05](05-command-handling.md#replay)), loads the
remembered positions, and catches up. Replay itself gives no event to any processor.

- A processor with no remembered position starts at `0`: it is given the whole log, and its
  commands, being repeat-safe, are refused where already done.
- A position **past the head of the log** means the log was deleted and began again. It is
  brought back to the head: the processor is not stuck waiting for a `seq` that will not come.
- A caller that keeps no positions treats every processor as having been given the whole log, so
  that replay does not run old effects again.

## Draft notes

- The Nim kit keeps positions in a `Positions` object separate from the store, so the store
  interface stays `append`, `load` and `close`. `MemPositions` forgets on exit. `FilePositions`
  writes one JSON object of processor name to position (`{"StepRunner":10,"TurnRunner":10}`),
  replaced whole through a temporary file. That file form is the Nim kit's own, not part of this
  spec, as the SQLite row form is not part of chapter 4.
- Delivery is in one thread, inside the call that handles a command. Queues and threads are not
  designed yet.
- What a processor may assume after a log has forgotten events (outline item 14) is not written.
