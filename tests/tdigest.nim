## The state digest: the fixtures in spec/fixtures/digest/ (plain data any kit reads), and the
## digest of a running app across stores. Format: spec/fixtures/README.md.
import std/[unittest, os, strutils, json, sequtils]
import eversince
import ../examples/desk/desk

let dir = currentSourcePath().parentDir / ".." / "spec" / "fixtures" / "digest"

proc jsonLines(path: string): seq[JsonNode] =
  for line in lines(path):
    if line.strip.len > 0: result.add parseJson(line)

suite "fixtures: state digest":
  var names: seq[string]
  for c in jsonLines(dir / "cases.jsonl"):
    names.add c["name"].getStr
    test c["name"].getStr:
      if c.hasKey("text"):
        check toHex(fnv1a64(c["text"].getStr), 16).toLowerAscii == c["digest"].getStr
      else:
        check canonicalJson(c["value"]) == c["canonical"].getStr
        check digest(c["value"]) == c["digest"].getStr
  test "names in cases.jsonl are unique":
    check names.deduplicate.len == names.len

suite "state digest":
  test "NaN and infinity are not state":
    expect ValueError: discard digest(newJFloat(NaN))
    expect ValueError: discard digest(newJFloat(Inf))
  test "key order of the written state does not matter":
    check digest(parseJson("""{"a":1,"b":[1,2]}""")) == digest(parseJson("""{ "b": [1, 2], "a": 1 }"""))
  test "the same events folded into an app give the same digest, from any store":
    var tick = 1_700_000_000_000'i64
    var live = Runtime[DeskApp](store: MemStore())
    live.clock = proc (): int64 = tick
    runAgent = proc (game, text: string): seq[string] = @["On it."]
    for (name, data) in [("SendMessage", %*{"game": "cat", "text": "hello"}), ("PickAgent", %*{"game": "cat", "agent": "codex"})]:
      tick += 1000
      discard live.execute(name, data)
    let again = replay[DeskApp](live.store)
    check stateDigest(live.app) == stateDigest(again.app)
    check stateDigest(live.app).len == 16
    # a different state gives a different digest
    var other = Runtime[DeskApp](store: MemStore())
    other.clock = live.clock
    check stateDigest(other.app) != stateDigest(live.app)
