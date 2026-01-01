import child_process
import filepath
import gleam/bool
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import oas/json_schema
import roboc/files
import roboc/openrouter/client.{type Tool, Function}
import roboc/openrouter/types
import simplifile

pub fn handle_tool(tool: types.ToolCall) -> Result(String, String) {
  case tool.name {
    "find_files" -> find_files(tool.arguments)
    "read_files" -> read_files(tool.arguments)
    _ -> Error("unknown tool name")
  }
}

pub fn all_tools() -> List(Tool) {
  [
    find_files_tool(),
    read_files_tool(),
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

type ReadFiles {
  ReadFiles(paths: List(String))
}

fn read_files_decoder() -> decode.Decoder(ReadFiles) {
  use paths <- decode.field("paths", decode.list(decode.string))
  decode.success(ReadFiles(paths:))
}

fn read_files_tool() -> client.Tool {
  Function(
    name: "read_files",
    description: Some("Read complete file contents."),
    parameters: Some(
      json_schema.encode(
        json_schema.object([
          json_schema.field(
            "paths",
            json_schema.array(
              json_schema.Inline(json_schema.String(
                max_length: None,
                min_length: None,
                pattern: None,
                format: None,
                nullable: True,
                title: Some("paths"),
                description: Some(
                  "File to read. Must be a relative path in or below the current directory.",
                ),
                deprecated: False,
              )),
            ),
          ),
        ]),
      ),
    ),
    strict: None,
  )
}

fn read_files(args: String) -> Result(String, String) {
  files.get_cwd()
  |> result.map_error(fn(e) {
    "Failed to determine current working directory. Cowardly refusing to read files. get_cwd() returned error: "
    <> e
  })
  |> result.try(fn(cwd) {
    json.parse(args, read_files_decoder())
    |> result.map_error(fn(e) { string.inspect(e) })
    |> result.try(fn(files_to_read) {
      list.map(files_to_read.paths, fn(path) {
        // contains logic to return error if expanding above the current dir
        // e.g. src/../../file would return an error.
        let absolute_path_to_read = filepath.expand(path)
        let contains_upward_dir_traversal = string.contains(path, "..")
        case absolute_path_to_read, contains_upward_dir_traversal {
          Error(_), _ ->
            "Error expanding path to read for file path. Potentially expands above current directory. "
            <> path
          _, True -> "Error: Refusing to read above current directory"
          Ok(abs_read_path), False -> {
            use <- bool.guard(
              filepath.is_absolute(path)
                && !string.starts_with(abs_read_path, cwd),
              "Error: File read path is not in current working directory, refusing to read",
            )
            case simplifile.read(path) {
              Ok(contents) -> contents
              Error(e) ->
                "Error reading file '" <> path <> "'" <> string.inspect(e)
            }
          }
        }
      })
      |> string.join("\n")
      |> Ok
    })
  })
}
