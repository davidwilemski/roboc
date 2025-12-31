import roboc/openrouter/types
import gleam/json
import gleam/option.{type Option, None, Some}
import oas/json_schema
import roboc/openrouter/client.{type Tool, Function}

pub fn all_tools() -> List(Tool) {
  [
    find_files_tool(),
  ]
}

type FindFiles {
  FindFiles(dir: Option(String), pattern: Option(String))
}

fn find_files_json_schema() -> json_schema.Schema {
  json_schema.object([
    json_schema.optional_field("dir", json_schema.string()),
    json_schema.optional_field("pattern", json_schema.string()),
  ])
}

fn find_files_json_params() -> json.Json {
  json_schema.encode(find_files_json_schema())
}

pub fn find_files_tool() -> client.Tool {
  Function(
    name: "find_files",
    description: Some("find files at a path with or without a pattern"),
    parameters: Some(find_files_json_params()),
    strict: None,
  )
}
