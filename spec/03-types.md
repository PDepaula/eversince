# 3. Type names

Types in a model file are spelled the same way in every kit, so one model file serves them all.

| Type | Meaning | As JSON |
|---|---|---|
| `string` | UTF-8 text | string |
| `int` | signed 64-bit integer | number with no fraction |
| `float` | 64-bit floating point | number |
| `bool` | true or false | `true` or `false` |
| `list[T]` | ordered sequence of `T` | array |
| `optional[T]` | a `T` or nothing | the value, or `null` |
| a record name | a `record` block of that name | object, one key per field, keys as declared |

Rules:

- A type has no white space inside it: `list[ChatLine]`, not `list[ ChatLine ]`.
- **Times are whole milliseconds since the Unix epoch**, as `int`.
- **Money is never a `float`.** Use whole minor units (cents) as `int`.
- Nesting is allowed: `list[list[int]]`, `optional[list[ChatLine]]`.
- An event, a command's input and a view's state are each records in all but name: the field
  list gives the JSON object's keys.

## Draft notes

- The Nim prototype writes Nim's `seq[T]` as `list[T]` in the model line and passes every other
  type through as spelled. It has no `optional[T]` mapping yet (Nim's `Option` is not mapped).
- Field defaults, and what a decoder does when a stored event lacks a field, belong to the
  schema-change rules (outline item 13), not written yet.
