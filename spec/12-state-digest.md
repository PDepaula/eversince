# 12. State digest

A **state digest** is a short hash of an app's views after a fold. Two runs that folded the same
events have the same digest, whichever store the events came from, whichever kit folded them. It
is how "replay gives the same state" is checked without comparing every field.

The digest is for noticing drift. It is not a security measure: FNV-1a is not collision resistant.

## The state

The state is one JSON object with a member for each view: the view's name with its first letter
in lower case (`Chat` is `chat`), and the view's fields as its value. Fields are written as in
[03-types.md](03-types.md). This is the same object the `view` check of a scenario reads
([11-scenarios.md](11-scenarios.md#fields)).

## Canonical JSON

The state is written as one text, so that equal states give equal bytes:

- Objects: members sorted by key, comparing the keys' UTF-8 bytes (which is code point order, not
  UTF-16 order). `{`, `"key":value` members joined by `,`, `}`.
- Arrays: elements in order, joined by `,`, between `[` and `]`.
- No white space outside strings.
- Strings: between `"`; `"` is written `\"`, `\` is `\\`, and the control characters below
  U+0020 are written `\b`, `\f`, `\n`, `\r`, `\t` where JSON has a short form and `\u00xx`
  (lower-case hex) otherwise. Nothing else is escaped: `/`, U+007F and all non-ASCII text are
  written as UTF-8.
- `null`, `true` and `false` as they are.
- Integers: decimal digits, a leading `-` if negative, no `+`, no leading zeros. They are 64-bit
  signed.
- Other numbers: the shortest decimal digits that read back as the same IEEE double, laid out as
  ECMAScript's `Number.prototype.toString` does it (the number is `0.d1d2...dk × 10^n`: plain
  digits when `k <= n <= 21`, a decimal point inside the digits when `0 < n <= 21`, `0.000ddd`
  when `-6 < n <= 0`, otherwise `d.ddde+x` or `d.ddde-x`). `-0` is written `0`. A number with no
  fraction is therefore written as an integer: `1.0` and `1` are the same text. NaN and infinity
  are not JSON; a kit MUST refuse them, not hash them.

## The hash

FNV-1a, 64 bits, over the bytes of the canonical text: start with `14695981039346656037`; for each
byte, xor it in, then multiply by `1099511628211`, modulo 2^64. The digest is the result as 16
lower-case hex digits.

```
hash("")       = cbf29ce484222325
hash("a")      = af63dc4c8601ec8c
hash("foobar") = 85944171f73967e8
```

## What the digest says

- Equal digests: the states are equal, up to a collision.
- It says nothing about the order the events came in, nor about what is in the log beyond what
  the views kept.
- A log that has forgotten ([14-forgetting.md](14-forgetting.md)) folds to the state of the events
  it still holds. Its digest can differ from the digest of the live state before the forgetting.

## Fixtures

[`fixtures/digest/cases.jsonl`](fixtures/digest/cases.jsonl) holds the canonical text and digest of
values and of texts; a log case in [`fixtures/log/cases.jsonl`](fixtures/log/cases.jsonl) carries
the digest of the desk's state after folding its events (`then.digest`).
See [`fixtures/README.md`](fixtures/README.md).

## Draft notes

- The prototype hashed `$(%app)` with Nim's `hash`, which is Nim-only and differs between 32 and
  64 bit builds. It is replaced by this definition.
