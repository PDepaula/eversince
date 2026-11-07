## The state digest: a short stable hash of folded state, so that "replay gives the same state"
## can be checked across stores, across runs and, later, across kits. Defined in
## `spec/12-state-digest.md`; the fixtures in `spec/fixtures/digest/` pin it down.
##
## The state is written as canonical JSON (keys sorted, no white space, one form for each number)
## and the bytes are hashed with 64-bit FNV-1a. The digest is for noticing drift, not for security.

import std/[json, algorithm, strutils]
import ./types

proc esNumber(f: float): string =
  ## A float as ECMAScript's `Number.prototype.toString` writes it: the shortest digits that read
  ## back as the same double, plain between 1e-6 and 1e21, exponent form outside. `-0` is `0`.
  if f != f or f == Inf or f == NegInf:
    raise newException(ValueError, "state digest: NaN and infinity are not JSON")
  if f == 0: return "0"
  if f < 0: return "-" & esNumber(-f)
  # Nim's `$` gives the shortest round-trip digits; take them apart and write them again.
  let s = $f
  let e = s.find({'e', 'E'})
  let (mant, exp10) = if e < 0: (s, 0) else: (s[0 ..< e], parseInt(s[e + 1 .. ^1]))
  let dot = mant.find('.')
  var digits = if dot < 0: mant else: mant[0 ..< dot] & mant[dot + 1 .. ^1]
  var n = (if dot < 0: mant.len else: dot) + exp10 ## the decimal point sits after n digits
  while digits.len > 1 and digits[0] == '0':
    digits = digits[1 .. ^1]
    dec n
  digits = digits.strip(leading = false, chars = {'0'})
  let k = digits.len
  if k <= n and n <= 21: digits & repeat('0', n - k)
  elif 0 < n and n <= 21: digits[0 ..< n] & "." & digits[n .. ^1]
  elif -6 < n and n <= 0: "0." & repeat('0', -n) & digits
  else:
    let x = n - 1
    let sign = if x < 0: "-" else: "+"
    (if k == 1: digits else: digits[0 .. 0] & "." & digits[1 .. ^1]) & "e" & sign & $abs(x)

proc addString(result: var string, s: string) =
  ## Quotes and backslashes and the control characters below 0x20 are escaped; everything else,
  ## `/` and non-ASCII text included, is written as it is (UTF-8).
  result.add '"'
  for c in s:
    case c
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    of '\b': result.add "\\b"
    of '\f': result.add "\\f"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    of '\0' .. '\x07', '\x0b', '\x0e' .. '\x1f': result.add "\\u00" & toHex(ord(c), 2).toLowerAscii
    else: result.add c
  result.add '"'

proc addCanonical(result: var string, n: JsonNode) =
  case n.kind
  of JNull: result.add "null"
  of JBool: result.add(if n.bval: "true" else: "false")
  of JInt: result.add $n.num
  of JFloat: result.add esNumber(n.fnum)
  of JString: result.addString n.str
  of JArray:
    result.add '['
    for i, x in n.elems:
      if i > 0: result.add ','
      result.addCanonical x
    result.add ']'
  of JObject:
    var keys: seq[string]
    for k, _ in n: keys.add k
    keys.sort() # byte order of the UTF-8 text, which is code point order
    result.add '{'
    for i, k in keys:
      if i > 0: result.add ','
      result.addString k
      result.add ':'
      result.addCanonical n[k]
    result.add '}'

proc canonicalJson*(n: JsonNode): string =
  ## The one text a value has: keys sorted, no white space, numbers in one form. An integer and a
  ## float with the same value are the same text (`1` and `1.0` both give `1`).
  result.addCanonical n

proc fnv1a64*(s: string): uint64 =
  ## 64-bit FNV-1a of the bytes of `s`.
  result = 14695981039346656037'u64
  for c in s:
    result = (result xor uint64(ord(c))) * 1099511628211'u64

proc digest*(state: JsonNode): string =
  ## 16 lower-case hex digits: FNV-1a 64 of the canonical JSON of `state`.
  toHex(fnv1a64(canonicalJson(state)), 16).toLowerAscii

proc stateDigest*[A](app: A): string =
  ## The digest of an app's views, as `%app` gives them: the same for any run that folded the same events.
  digest(%app)
