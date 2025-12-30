import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

pub fn json_decode_error_to_string(e: json.DecodeError) -> String {
  case e {
    json.UnexpectedEndOfInput -> "UnexpectedEndOfInput"
    json.UnexpectedByte(b) -> "UnexpectedByte: " <> b
    json.UnexpectedSequence(s) -> "Unexpected Sequence: " <> s
    json.UnableToDecode(errs) ->
      string.join(list.map(errs, format_decode_error), "\n")
  }
}

pub fn format_decode_error(e: decode.DecodeError) -> String {
  "DecodeError(expected: "
  <> e.expected
  <> ", found: "
  <> e.found
  <> " path: "
  <> string.join(e.path, "/")
  <> ")"
}
