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
import simplifile

pub fn handle_tool(tool: types.ToolCall) -> Result(String, String) {
  case tool.name {
    "find_files" -> find_files(tool.arguments)
    "grep_files" -> grep_files(tool.arguments)
    "read_files" -> read_files(tool.arguments)
    "apply_patch" -> apply_patch(tool.arguments)
    _ -> Error("unknown tool name")
  }
}

pub fn all_tools() -> List(Tool) {
  [
    find_files_tool(),
    grep_files_tool(),
    read_files_tool(),
    apply_patch_tool(),
  ]
}

type FindFiles {
  FindFiles(dir: Option(String), pattern: Option(String))
}

fn find_files_decoder() -> decode.Decoder(FindFiles) {
  use dir <- decode.optional_field("dir", None, decode.optional(decode.string))
  use pattern <- decode.optional_field(
    "pattern",
    None,
    decode.optional(decode.string),
  )
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

type GrepFiles {
  GrepFiles(
    pattern: String,
    context: Option(Int),
    case_insensitive: Option(Bool),
  )
}

fn grep_files_decoder() -> decode.Decoder(GrepFiles) {
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

fn grep_files(args: String) -> Result(String, String) {
  json.parse(args, grep_files_decoder())
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

pub fn grep_files_tool() -> client.Tool {
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
