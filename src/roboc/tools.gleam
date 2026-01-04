import child_process
import filepath
import gleam/bool
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import in
import oas/json_schema
import roboc/files
import roboc/openrouter/client.{type Tool, Function}
import roboc/openrouter/types
import roboc/tools/find_files
import roboc/tools/grep_files
import simplifile

pub fn handle_tool(tool: types.ToolCall) -> Result(String, String) {
  case tool.name {
    "find_files" -> find_files.handle(tool.arguments)
    "grep_files" -> grep_files.handle(tool.arguments)
    "read_files" -> read_files(tool.arguments)
    "apply_patch" -> apply_patch(tool.arguments)
    "write_file" -> write_file(tool.arguments)
    _ -> Error("unknown tool name")
  }
}

pub fn all_tools() -> List(Tool) {
  [
    find_files.tool(),
    grep_files.tool(),
    read_files_tool(),
    apply_patch_tool(),
    write_file_tool(),
  ]
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

type ApplyPatch {
  ApplyPatch(patch: String)
}

fn apply_patch_decoder() -> decode.Decoder(ApplyPatch) {
  use patch <- decode.field("patch", decode.string)
  decode.success(ApplyPatch(patch:))
}

pub fn apply_patch_tool() -> client.Tool {
  Function(
    name: "apply_patch",
    description: Some(
      "Apply a unified diff patch to modify files. The patch should be in unified diff format. "
      <> "User will be prompted to approve the patch before it is applied.",
    ),
    parameters: Some(
      json_schema.encode(
        json_schema.object([
          json_schema.field(
            "patch",
            json_schema.String(
              max_length: None,
              min_length: None,
              pattern: None,
              format: None,
              nullable: False,
              title: Some("patch"),
              description: Some(
                "Unified diff format patch to apply. Should include file headers "
                <> "(--- a/path +++ b/path) and hunks with context.",
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

fn apply_patch(args: String) -> Result(String, String) {
  use patch_data <- result.try(
    json.parse(args, apply_patch_decoder())
    |> result.map_error(fn(e) { string.inspect(e) }),
  )

  // TODO Read patch headers to confirm file(s) being modified are in the directory.
  // For now, user approval makes this safe enough to start testing.

  // Display the patch to the user
  // TODO provide a better abstraction for exposing user interactions in tool
  // calls so that terminal (or other UI) interactions can be maintained
  // separately from tool concerns
  io.println("\n=== Proposed Patch ===")
  io.println(patch_data.patch)
  io.println("======================\n")
  io.print("Apply this patch? (y/n): ")

  // Get user approval
  use approval <- result.try(
    in.read_line()
    |> result.map_error(fn(_) { "Failed to read user input" }),
  )

  case string.trim(approval) |> string.lowercase {
    "y" | "yes" -> {
      let subj = process.new_subject()
      // Apply the patch using the `patch` command
      child_process.new_with_path("patch")
      |> child_process.arg("-p1")
      |> child_process.on_exit(fn(status_code) {
        process.send(subj, status_code)
      })
      // Strip 1 directory level (standard for git diffs)
      |> child_process.spawn
      |> result.map_error(fn(e) {
        "error starting patch command: " <> string.inspect(e)
      })
      |> result.try(fn(process) {
        child_process.write(process, patch_data.patch)
        child_process.close(process)

        case process.receive(subj, within: 5000) {
          Ok(0) -> Ok("Patch applied successfully")
          Ok(code) -> Error("Patch failed to apply: " <> int.to_string(code))
          Error(_) -> {
            child_process.stop(process)
            Error("Timed out waiting for patch application.")
          }
        }
      })
    }
    _ ->
      Error(
        "Patch application cancelled by user. Ask if they want to do something else.",
      )
  }
}

type WriteFile {
  WriteFile(path: String, content: String, append: Option(Bool))
}

fn write_file_decoder() -> decode.Decoder(WriteFile) {
  use path <- decode.field("path", decode.string)
  use content <- decode.field("content", decode.string)
  use append <- decode.optional_field(
    "append",
    None,
    decode.optional(decode.bool),
  )
  decode.success(WriteFile(path:, content:, append:))
}

pub fn write_file_tool() -> client.Tool {
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

fn write_file(args: String) -> Result(String, String) {
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
    json.parse(args, write_file_decoder())
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
  io.println("--- Content ---")
  io.println(write_data.content)
  io.println("--- End Content ---")
  io.println("===============================\n")
  io.print("Write this file? (y/n): ")

  // Get user approval
  use approval <- result.try(
    in.read_line()
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
