import child_process
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import oas/json_schema
import roboc/openrouter/client.{Function}

type GrepFiles {
  GrepFiles(
    pattern: String,
    context: Option(Int),
    case_insensitive: Option(Bool),
  )
}

fn decoder() -> decode.Decoder(GrepFiles) {
  use pattern <- decode.field("pattern", decode.string)
  use context <- decode.optional_field(
    "context",
    None,
    decode.optional(decode.int),
  )
  use case_insensitive <- decode.optional_field(
    "case_insensitive",
    None,
    decode.optional(decode.bool),
  )
  decode.success(GrepFiles(pattern:, context:, case_insensitive:))
}

pub fn handle(args: String) -> Result(String, String) {
  json.parse(args, decoder())
  |> result.map_error(fn(e) { string.inspect(e) })
  |> result.try(fn(grep) {
    let cmd = child_process.new_with_path("rg")

    let cmd = case grep.case_insensitive {
      Some(True) -> child_process.arg(cmd, "-i")
      _ -> cmd
    }

    case grep.context {
      Some(context_lines) ->
        cmd
        |> child_process.arg("-C")
        |> child_process.arg(int.to_string(context_lines))
      None -> cmd
    }
    |> child_process.arg("--color=never")
    |> child_process.arg(grep.pattern)
    |> child_process.arg(".")
    |> child_process.run
    |> result.map_error(fn(e) { string.inspect(e) })
  })
  |> result.try(fn(output) {
    case output.status_code {
      0 -> Ok(output.output)
      1 -> Ok("No matches found")
      _ -> Error(output.output)
    }
  })
}

pub fn tool() -> client.Tool {
  Function(
    name: "grep_files",
    description: Some(
      "Search for a pattern in files using ripgrep. Returns matching lines with optional context.",
    ),
    parameters: Some(
      json_schema.encode(
        json_schema.object([
          json_schema.field(
            "pattern",
            json_schema.String(
              max_length: None,
              min_length: None,
              pattern: None,
              format: None,
              nullable: False,
              title: Some("pattern"),
              description: Some("Regular expression pattern to search for"),
              deprecated: False,
            ),
          ),
          json_schema.optional_field("context", json_schema.integer()),
          json_schema.optional_field("case_insensitive", json_schema.boolean()),
        ]),
      ),
    ),
    strict: None,
  )
}
