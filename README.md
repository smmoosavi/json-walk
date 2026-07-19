# jsonwalk (Bash JSON Walker)

`jsonwalk` is a **pure Bash streaming JSON parser** that walks through JSON and emits parsing events.  
Instead of building a full object model, it produces **events for each structural element**, similar to SAX-style XML parsers.

This makes it useful for:

- Processing JSON in **shell scripts without `jq`**
- Building lightweight JSON visitors in Bash

The parser follows the JSON grammar and supports:

- objects
- arrays
- strings, preserving their raw JSON content inside quotes
- numbers
- booleans
- null

---

# Installation

Copy the script into your project and source it:

```bash
source jsonwalk.sh
```

---

# Basic Usage

### Print parsing events

```bash
json_walk '{"label": "abc", "items": [1, 2, 3]}'
```

Output:

```
start_object
key	label
string	abc
key	items
start_array
number	1
number	2
number	3
end_array
end_object
```

Fields are separated by **tabs**. String values are emitted as the exact content inside their JSON double quotes, so JSON escapes are preserved.

---

# Visitor Mode

Instead of printing events, you can provide a **visitor function**.

```bash
json_walk "$json" my_visitor
```

Example:

```bash
my_visitor() {
    event=$1
    value=${2:-}
    echo "EVENT: $event VALUE: $value"
}
```

Usage:

```bash
json='{"a":1,"b":2}'
json_walk "$json" my_visitor
```

Output:

```
EVENT: start_object VALUE: 
EVENT: key VALUE: a
EVENT: number VALUE: 1
EVENT: key VALUE: b
EVENT: number VALUE: 2
EVENT: end_object VALUE: 
```

Visitor arguments:

```
visitor EVENT [VALUE]
```

---

# Event Types

The parser emits the following events:

### Structural events

```
start_object
end_object
start_array
end_array
```

### Object keys

```
key <key>
```

### Values

```
string <raw-content-inside-json-quotes>
number <value>
boolean <true|false>
null
```

For example, `"\u0041"` emits `string	\u0041`, while `"AA"` emits `string	AA`.

---

# Example: Extract Values

Example visitor that prints only values of id:

```bash
is_id_key=false
print_ids() {
    event=$1
    value=${2:-}

    if [[ "$event" == "key" && "$value" == "id" ]]; then
        is_id_key=true
    elif $is_id_key; then
        echo "ID: $value"
        is_id_key=false
    fi
}

json_walk '[{"id": 4}, {"id": 5}]' print_ids
# ID: 4
# ID: 5
```

---

# Parser Behavior

- Fully validates JSON structure
- Validates escaped characters:
  - `\" \\ \/ \b \f \n \r \t`
- Validates Unicode escapes (`\uXXXX`)
- Validates UTF‑16 surrogate pairs
- Preserves raw string content instead of decoding escapes during walking
- Rejects:
  - unterminated strings
  - invalid escape sequences
  - malformed numbers
  - invalid JSON structure

Whitespace is skipped.

---

# Error Handling

If parsing fails, the parser prints an error to **stderr** and returns non‑zero.

Example:

```
JSON parse error near position 42
```

Typical failure cases:

- malformed JSON
- invalid unicode escape
- unexpected characters
- missing separators (`:`, `,`, etc.)

---

# Function Reference

### `json_walk JSON [VISITOR]`

Walks through the JSON string.

Parameters:

- `JSON` — JSON document string
- `VISITOR` (optional) — function called for each event

Behavior:

- If `VISITOR` is provided, events are sent to it
- Otherwise events are printed to stdout

### `json_walk_decode_string STRING_CONTENT`

Decodes raw JSON string content, without surrounding double quotes.

```bash
json_walk_decode_string '\u0041'
# A
```

The decoded value is printed to stdout and also assigned to `REPLY`.

---

# Design Notes

- Written entirely in **Bash**
- No external dependencies
- Event-driven architecture
- Maintains minimal parser state:
  - `jsonwalk_json`
  - `jsonwalk_pos`
  - `jsonwalk_visitor`

This makes it suitable for **minimal environments** where tools like `jq` are unavailable.

---

# Limitations

- Entire JSON document must fit in memory
- Only parses from a **string**, not a stream
- Performance is slower than compiled parsers
- Bash ≥4 recommended

---

# License

MIT
