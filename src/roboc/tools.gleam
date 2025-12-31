import child_process
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import oas/json_schema
import roboc/openrouter/client.{type Tool, Function}
import roboc/openrouter/types

pub fn handle_tool(tool: types.ToolCall) -> Result(String, String) {
  case tool.name {
    "find_files" -> find_files(tool.arguments)
    _ -> Error("unknown tool name")
  }
}

pub fn all_tools() -> List(Tool) {
  [
    find_files_tool(),
  ]
}

type FindFiles {
  FindFiles(dir: Option(String), pattern: Option(String))
}

fn find_files_decoder() -> decode.Decoder(FindFiles) {
  use dir <- decode.field("dir", decode.optional(decode.string))
  use pattern <- decode.field("pattern", decode.optional(decode.string))
  decode.success(FindFiles(dir:, pattern:))
}

fn find_files(args: String) -> Result(String, String) {
  json.parse(args, find_files_decoder())
  |> result.map_error(fn(e) { string.inspect(e) })
  |> result.try(fn(find) {
    let path = option.unwrap(find.dir, ".")
    let pattern = option.unwrap(find.pattern, ".*")
    child_process.new_with_path("fd")
    |> child_process.cwd(path)
    |> child_process.arg(pattern)
    |> child_process.run
    |> result.map_error(fn(e) { string.inspect(e) })
  })
  |> result.try(fn(output) {
    case output.status_code {
      0 -> Ok(output.output)
      _ -> Error(output.output)
    }
  })
}

pub fn find_files_tool() -> client.Tool {
  Function(
    name: "find_files",
    description: Some("find files at a path with or without a pattern"),
    parameters: Some(
      json_schema.encode(
        json_schema.object([
          json_schema.optional_field("dir", json_schema.string()),
          json_schema.optional_field(
            "pattern",
            json_schema.String(
              max_length: None,
              min_length: None,
              pattern: None,
              format: None,
              nullable: True,
              title: Some("pattern"),
              description: Some(
                "pattern to use to filter files, in regex format",
              ),
              deprecated: False,
            ),
          ),
        ]),
      ),
    ),
    strict: None,
  )
}
