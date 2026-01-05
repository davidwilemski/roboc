/// UTF-8 safe input reading using Erlang's native IO functions
/// This module provides functions that properly handle Unicode/emoji characters
/// which the `in` library cannot handle due to Latin1 encoding limitations.
/// Read a line from standard input with proper UTF-8/Unicode support
/// Returns the line with the trailing newline included
pub fn read_line() -> Result(String, Nil) {
  do_read_line()
}

@external(erlang, "roboc_ffi", "read_line_utf8")
fn do_read_line() -> Result(String, Nil)
