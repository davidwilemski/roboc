import filepath
import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import oas/json_schema
import roboc/files
import roboc/openrouter/client.{Function}
import simplifile

type ReadFiles {
  ReadFiles(paths: List(String))
}

fn decoder() -> decode.Decoder(ReadFiles) {
  use paths <- decode.field("paths", decode.list(decode.string))
  decode.success(ReadFiles(paths:))
}

pub fn handle(args: String) -> Result(String, String) {
  files.get_cwd()
  |> result.map_error(fn(e) {
    "Failed to determine current working directory. Cowardly refusing to read files. get_cwd() returned error: "
    <> e
  })
  |> result.try(fn(cwd) {
    json.parse(args, decoder())
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

pub fn summarize(args: String) -> String {
  case json.parse(args, decoder()) {
    Ok(data) -> {
      let file_count = list.length(data.paths)
      case file_count {
        1 -> "(" <> string.join(data.paths, ", ") <> ")"
        n -> "(" <> int.to_string(n) <> " files)"
      }
    }
    Error(_) -> "(failed to parse args)"
  }
}

pub fn tool() -> client.Tool {
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
