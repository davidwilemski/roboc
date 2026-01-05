import filepath
import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import oas/json_schema
import roboc/diff
import roboc/files
import roboc/io as roboc_io
import roboc/openrouter/client.{Function}
import simplifile

type WriteFile {
  WriteFile(path: String, content: String, append: Option(Bool))
}

fn decoder() -> decode.Decoder(WriteFile) {
  use path <- decode.field("path", decode.string)
  use content <- decode.field("content", decode.string)
  use append <- decode.optional_field(
    "append",
    None,
    decode.optional(decode.bool),
  )
  decode.success(WriteFile(path:, content:, append:))
}

pub fn handle(args: String) -> Result(String, String) {
  // Get cwd for security validation
  use cwd <- result.try(
    files.get_cwd()
    |> result.map_error(fn(e) {
      "Failed to determine current working directory. Cowardly refusing to write file. get_cwd() returned error"
      <> e
    }),
  )

  // Parse arguments
  use write_data <- result.try(
    json.parse(args, decoder())
    |> result.map_error(fn(e) { string.inspect(e) }),
  )

  let path = write_data.path

  // Security checks (same as read_files)
  let absolute_path = filepath.expand(path)
  let contains_upward_dir_traversal = string.contains(path, "..")

  use <- bool.guard(
    contains_upward_dir_traversal,
    Error("Error: Refusing to write above current directory"),
  )

  use abs_path <- result.try(
    absolute_path
    |> result.map_error(fn(_) {
      "Error expanding path for file write. Potentially expands above current directory: "
      <> path
    }),
  )

  use <- bool.guard(
    filepath.is_absolute(path) && !string.starts_with(abs_path, cwd),
    Error(
      "Error: File write path is not in current working directory, refusing to write",
    ),
  )

  let should_append = option.unwrap(write_data.append, False)

  // Check if file exists for the prompt message
  let file_exists = simplifile.is_file(path)
  use <- bool.guard(
    result.is_error(file_exists),
    Error(
      "Error: failed to confirm file existence. Check permissions on file path.",
    ),
  )

  let assert Ok(file_exists) = file_exists as "result checked with guard"
  let action_description = case file_exists, should_append {
    True, True -> "APPEND to existing file"
    True, False -> "OVERWRITE existing file"
    False, _ -> "CREATE new file"
  }

  // Display the proposed write to the user
  io.println("\n=== Proposed File Write ===")
  io.println("Action: " <> action_description)
  io.println("Path: " <> path)

  // For overwrites, show a diff instead of full content
  case file_exists, should_append {
    True, False -> {
      // Read existing content and show diff
      case simplifile.read(path) {
        Ok(old_content) -> {
          case diff.unified_diff(path, old_content, write_data.content) {
            Ok(diff_output) -> {
              io.println("--- Diff ---")
              io.println(diff_output)
              io.println("--- End Diff ---")
            }
            Error(_) -> {
              // Fallback to showing new content if diff fails
              io.println("--- New Content ---")
              io.println(write_data.content)
              io.println("--- End Content ---")
            }
          }
        }
        Error(_) -> {
          // If we can't read the file, just show new content
          io.println("--- New Content ---")
          io.println(write_data.content)
          io.println("--- End Content ---")
        }
      }
    }
    _, _ -> {
      // For new files or appends, show the content
      io.println("--- Content ---")
      io.println(write_data.content)
      io.println("--- End Content ---")
    }
  }

  io.println("===============================\n")
  io.print("Write this file? (y/n): ")

  // Get user approval
  use approval <- result.try(
    roboc_io.read_line()
    |> result.map_error(fn(_) { "Failed to read user input" }),
  )

  case string.trim(approval) |> string.lowercase {
    "y" | "yes" -> {
      let write_result = case should_append {
        True -> simplifile.append(path, write_data.content)
        False -> simplifile.write(path, write_data.content)
      }

      case write_result {
        Ok(_) -> Ok("File written successfully: " <> path)
        Error(e) ->
          Error("Failed to write file '" <> path <> "': " <> string.inspect(e))
      }
    }
    _ ->
      Error(
        "File write cancelled by user. Ask if they want to do something else.",
      )
  }
}

pub fn summarize(args: String) -> String {
  case json.parse(args, decoder()) {
    Ok(data) -> {
      let action = case data.append {
        Some(True) -> "append to"
        _ -> "write"
      }
      let content_len = string.length(data.content)
      "("
      <> action
      <> " "
      <> data.path
      <> ", "
      <> int.to_string(content_len)
      <> " chars)"
    }
    Error(_) -> "(failed to parse args)"
  }
}

pub fn tool() -> client.Tool {
  Function(
    name: "write_file",
    description: Some(
      "Write content to a file. Creates the file if it doesn't exist, or overwrites if it does. "
      <> "Set append to true to append to the file instead. User will be prompted to approve the write before it is executed.",
    ),
    parameters: Some(
      json_schema.encode(
        json_schema.object([
          json_schema.field(
            "path",
            json_schema.String(
              max_length: None,
              min_length: None,
              pattern: None,
              format: None,
              nullable: False,
              title: Some("path"),
              description: Some(
                "File path to write to. Must be a relative path in or below the current directory.",
              ),
              deprecated: False,
            ),
          ),
          json_schema.field("content", json_schema.string()),
          json_schema.optional_field("append", json_schema.boolean()),
        ]),
      ),
    ),
    strict: None,
  )
}
