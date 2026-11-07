## Plain types shared by every part of the kit: the event envelope, the context a decision is
## given, and a decision's result. Nothing here reads a clock, a file or the environment.

import std/[json, strutils]
export json

type
  Envelope* = object
    seq*: int64   ## position in the log, 1-based; stamped by the shell on append
    at*: int64    ## milliseconds since the epoch; stamped by the shell on append
    kind*: string
    data*: JsonNode

  Ctx* = object   ## everything a decision may know about "now": handed in, never read
    now*: int64
    nextSeq*: int64

  Decision* = object
    refused*: bool
    code*, message*: string
    events*: seq[Envelope]

  IssueProc* = proc (name: string, data: JsonNode)

func envelopeOf*[T](kind: string, e: T): Envelope =
  Envelope(kind: kind, data: %e)

proc lowerFirst*(s: string): string = s[0].toLowerAscii & s[1 .. ^1]
