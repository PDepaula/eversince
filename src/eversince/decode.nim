## Tolerant decoding of a stored event (`spec/13-tolerant-decoding.md`): a stored payload becomes
## the event's Nim type, whatever shape the event had when it was written.
##   - a field the stored JSON lacks takes the type's default (`string` "", numbers 0, `bool`
##     false, `seq` empty, a record with every field defaulted);
##   - a key the type does not have is ignored;
##   - a field present with the wrong JSON type fails with a `DecodeError` naming the event, the
##     field and the event's position in the log.
## Records inside an event, and the elements of a list, are decoded the same way. A type of any
## other kind (a generic type such as `Option`, `Table`, `HashSet`, an enum, ...) is left to
## `std/json`'s `to`, which stays strict.

import std/[json, typetraits]
import ./types

type
  DecodeError* = object of ValueError
    ## A stored event does not fit its type. `event` is the block, `field` the path to the field
    ## (`lines[2].who`, empty when the payload itself is not an object), `position` the event's
    ## `seq`.
    event*, field*: string
    position*: int64

proc kindName(n: JsonNode): string =
  case n.kind
  of JString: "string"
  of JInt: "int"
  of JFloat: "float"
  of JBool: "bool"
  of JNull: "null"
  of JObject: "object"
  of JArray: "list"

proc wrong(event, path: string, position: int64, expected: string, found: JsonNode): ref DecodeError =
  let msg = "event " & event & " at position " & $position &
            (if path.len > 0: ", field " & path else: ", its data") &
            ": expected " & expected & ", found " & kindName(found)
  (ref DecodeError)(msg: msg, event: event, field: path, position: position)

proc fill[T](dst: var T, n: JsonNode, event, path: string, position: int64) =
  when T is string:
    if n.kind != JString: raise wrong(event, path, position, "string", n)
    dst = n.str
  elif T is bool:
    if n.kind != JBool: raise wrong(event, path, position, "bool", n)
    dst = n.bval
  elif T is SomeInteger:
    if n.kind != JInt: raise wrong(event, path, position, "int", n)
    let v = n.num
    when T is SomeUnsignedInt:
      if v < 0 or (sizeof(T) < 8 and v > BiggestInt(high(T))): raise wrong(event, path, position, "int in range", n)
    elif sizeof(T) < 8:
      if v < BiggestInt(low(T)) or v > BiggestInt(high(T)): raise wrong(event, path, position, "int in range", n)
    dst = T(v)
  elif T is SomeFloat:
    if n.kind notin {JFloat, JInt}: raise wrong(event, path, position, "float", n)
    dst = T(n.getFloat)
  elif T is seq:
    if n.kind != JArray: raise wrong(event, path, position, "list", n)
    dst = newSeq[typeof(dst[0])](n.len)
    for i in 0 ..< n.len: fill(dst[i], n[i], event, path & "[" & $i & "]", position)
  elif T is object and '[' notin name(T):
    if n.kind != JObject: raise wrong(event, path, position, "object", n)
    for name, field in fieldPairs(dst):
      if n.hasKey(name):
        fill(field, n[name], event, (if path.len > 0: path & "." else: "") & name, position)
  else:
    try: dst = n.to(T)
    except CatchableError as e:
      let msg = "event " & event & " at position " & $position & ", field " & path & ": " & e.msg
      raise (ref DecodeError)(msg: msg, event: event, field: path, position: position)

proc decodeEvent*[T](env: Envelope): T =
  ## The stored event `env` as a `T`, tolerant as the module says. Raises `DecodeError`.
  fill(result, env.data, env.kind, "", env.seq)
