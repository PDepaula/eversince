## Tolerant decoding (spec 13), on types of its own: defaults, ignored keys, wrong types, nesting.
import std/[unittest, strutils, options, tables]
import eversince

type
  Line = object
    who: string
    text: string
    stars: int
  Note = object
    game: string
    turn: int
    ratio: float
    done: bool
    lines: seq[Line]
    pick: Option[string]
    small: uint8
    nested: Line
    tags: Table[string, int]

proc env(data: string, seq = 7'i64): Envelope =
  Envelope(seq: seq, at: 1, kind: "Note", data: parseJson(data))

proc refusal(data: string): ref DecodeError =
  try: discard decodeEvent[Note](env(data))
  except DecodeError as e: return e

suite "tolerant decoding":
  test "a complete event decodes as before":
    let n = decodeEvent[Note](env("""{"game":"cat","turn":2,"ratio":1.5,"done":true,
      "lines":[{"who":"you","text":"hi","stars":3}],"pick":"x","small":200,"nested":{"who":"a","text":"b","stars":1}}"""))
    check n.game == "cat" and n.turn == 2 and n.ratio == 1.5 and n.done
    check n.lines.len == 1 and n.lines[0].stars == 3
    check n.pick == some("x") and n.small == 200 and n.nested.text == "b"

  test "every missing field takes its default":
    let n = decodeEvent[Note](env("{}"))
    check n == Note()
    check n.pick.isNone and n.lines.len == 0

  test "an unknown key is ignored":
    check decodeEvent[Note](env("""{"game":"cat","effort":"high","extra":{"a":1}}""")).game == "cat"

  test "a record inside the event is tolerant too, in a field and in a list":
    let n = decodeEvent[Note](env("""{"lines":[{"who":"you"},{"text":"t","new":1}],"nested":{"stars":4}}"""))
    check n.lines == @[Line(who: "you"), Line(text: "t")]
    check n.nested == Line(stars: 4)

  test "an int is accepted for a float field":
    check decodeEvent[Note](env("""{"ratio":2}""")).ratio == 2.0

  test "a wrong type names the event, the field and the position":
    let e = refusal("""{"game":"cat","turn":"one"}""")
    check e != nil
    check e.event == "Note" and e.field == "turn" and e.position == 7
    check e.msg == "event Note at position 7, field turn: expected int, found string"

  test "the path reaches into lists and records":
    check refusal("""{"lines":[{"who":"a"},{"who":5}]}""").field == "lines[1].who"
    check refusal("""{"nested":{"stars":"x"}}""").field == "nested.stars"

  test "each primitive refuses another kind, and null":
    for data in ["""{"game":1}""", """{"turn":1.5}""", """{"turn":null}""", """{"ratio":"1"}""",
                 """{"done":"yes"}""", """{"lines":{}}""", """{"lines":[1]}""", """{"game":null}""",
                 """{"small":300}""", """{"small":-1}"""]:
      check refusal(data) != nil

  test "data that is not an object is refused, naming the event and the position":
    let e = refusal("[1,2]")
    check e != nil and e.field == "" and e.position == 7
    check "event Note at position 7" in e.msg

  test "a type left to std/json stays strict, with the same error":
    let e = refusal("""{"pick":5}""")
    check e != nil and e.field == "pick" and e.event == "Note"

  test "a table field decodes its stored entries":
    let n = decodeEvent[Note](env("""{"tags":{"a":1,"b":2}}"""))
    check n.tags == {"a": 1, "b": 2}.toTable

  test "a wrong-typed table entry fails loudly":
    let e = refusal("""{"tags":{"a":"one"}}""")
    check e != nil and e.field == "tags" and e.event == "Note"
