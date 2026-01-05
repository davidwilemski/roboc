import filepath
import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import in
import oas/json_schema
import roboc/files
import roboc/openrouter/client.{Function}
import simplifile

type Replacement {
  Replacement(path: String, old_text: String, new_text: String)
}

type ReplaceText {
  ReplaceText(replacements: List(Replacement))
}

fn replacement_decoder() -> decode.Decoder(Replacement) {
  use path <- decode.field("path", decode.string)
  use old_text <- decode.field("old_text", decode.string)
  use new_text <- decode.field("new_text", decode.string)
  decode.success(Replacement(path:, old_text:, new_text:))
}

fn decoder() -> decode.Decoder(ReplaceText) {
  use replacements <- decode.field("replacements", decode.list(replacement_decoder()))
  decode.success(ReplaceText(replacements:))
}

pub fn handle(args: String) -> Result(String, String) {
  // Get cwd for security validation
  use cwd <- result.try(
    files.get_cwd()
    |> result.map_error(fn(e) {
      "Failed to determine current working directory. Cowardly refusing to replace text. get_cwd() returned error: "
      <> e
    }),
  )

  // Parse arguments
  use replace_data <- result.try(
    json.parse(args, decoder())
    |> result.map_error(fn(e) { string.inspect(e) }),
  )

  // Validate all paths first
  use validated_replacements <- result.try(
    validate_all_paths(replace_data.replacements, cwd)
  )

  // Preview all replacements
  use preview_results <- result.try(
    preview_replacements(validated_replacements)
  )

  // Show preview to user
  display_preview(preview_results)

  // Get user approval
  use approval <- result.try(
    in.read_line()
    |> result.map_error(fn(_) { "Failed to read user input" }),
  )

  case string.trim(approval) |> string.lowercase {
    "y" | "yes" -> apply_replacements(preview_results)
    _ -> Error("Text replacements cancelled by user. Ask if they want to do something else.")
  }
}

fn validate_all_paths(replacements: List(Replacement), cwd: String) -> Result(List(Replacement), String) {
  list.try_map(replacements, fn(replacement) {
    validate_path(replacement, cwd)
  })
}

fn validate_path(replacement: Replacement, cwd: String) -> Result(Replacement, String) {
  let path = replacement.path

  // Security checks
  let absolute_path = filepath.expand(path)
  let contains_upward_dir_traversal = string.contains(path, "..")

  use <- bool.guard(
    contains_upward_dir_traversal,
    Error("Error: Refusing to modify file above current directory: " <> path),
  )

  use abs_path <- result.try(
    absolute_path
    |> result.map_error(fn(_) {
      "Error expanding path for text replacement. Potentially expands above current directory: "
      <> path
    }),
  )

  use <- bool.guard(
    filepath.is_absolute(path) && !string.starts_with(abs_path, cwd),
    Error(
      "Error: File path is not in current working directory, refusing to modify: " <> path,
    ),
  )

  Ok(replacement)
}

type PreviewResult {
  PreviewResult(
    replacement: Replacement,
    file_content: String,
    new_content: String,
    found: Bool,
  )
}

fn preview_replacements(replacements: List(Replacement)) -> Result(List(PreviewResult), String) {
  list.try_map(replacements, fn(replacement) {
    use file_content <- result.try(
      simplifile.read(replacement.path)
      |> result.map_error(fn(e) {
        "Error reading file '" <> replacement.path <> "': " <> string.inspect(e)
      }),
    )

    let found = string.contains(file_content, replacement.old_text)
    let new_content = case found {
      True -> string.replace(file_content, replacement.old_text, replacement.new_text)
      False -> file_content
    }

    Ok(PreviewResult(
      replacement: replacement,
      file_content: file_content,
      new_content: new_content,
      found: found,
    ))
  })
}

fn display_preview(preview_results: List(PreviewResult)) -> Nil {
  let total_replacements = list.length(preview_results)
  let successful_replacements = list.count(preview_results, fn(p) { p.found })

  io.println("\n=== Proposed Text Replacements ===")
  io.println("Total replacements: " <> int.to_string(total_replacements))
  io.println("Found matches: " <> int.to_string(successful_replacements))

  list.each(preview_results, fn(preview) {
    io.println("\n--- File: " <> preview.replacement.path <> " ---")
    case preview.found {
      True -> {
        io.println("✓ Found text to replace")
        io.println("Old:")
        io.println(preview.replacement.old_text)
        io.println("New:")
        io.println(preview.replacement.new_text)

        // Show line context if old_text is short enough
        case string.length(preview.replacement.old_text) < 100 {
          True -> show_line_context(preview.file_content, preview.replacement.old_text)
          False -> Nil
        }
      }
      False -> {
        io.println("✗ Text not found: " <> string.inspect(preview.replacement.old_text))
      }
    }
  })

  io.println("\n===================================")
  io.print("Apply these replacements? (y/n): ")
}

fn show_line_context(content: String, old_text: String) -> Nil {
  let lines = string.split(content, "\n")
  case find_line_with_text(lines, old_text, 0) {
    Ok(line_num) -> {
      io.println("Context (line " <> int.to_string(line_num + 1) <> "): " <>
        result.unwrap(list.first(list.drop(lines, line_num - 1)), ""))
    }
    Error(_) -> Nil
  }
}

fn find_line_with_text(lines: List(String), text: String, line_num: Int) -> Result(Int, Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] -> {
      case string.contains(line, text) {
        True -> Ok(line_num)
        False -> find_line_with_text(rest, text, line_num + 1)
      }
    }
  }
}

fn apply_replacements(preview_results: List(PreviewResult)) -> Result(String, String) {
  let results = list.map(preview_results, fn(preview) {
    case preview.found {
      True -> {
        case simplifile.write(preview.replacement.path, preview.new_content) {
          Ok(_) -> Ok(preview.replacement.path)
          Error(e) -> Error("Failed to write " <> preview.replacement.path <> ": " <> string.inspect(e))
        }
      }
      False -> Ok(preview.replacement.path <> " (no changes)")
    }
  })

  let errors = list.filter_map(results, fn(r) {
    case r {
      Error(e) -> Ok(e)
      Ok(_) -> Error(Nil)
    }
  })

  case errors {
    [] -> {
      let successful = list.count(preview_results, fn(p) { p.found })
      Ok("Text replacements completed successfully: " <> int.to_string(successful) <> " replacement(s) made")
    }
    _ -> Error("Some replacements failed:\n" <> string.join(errors, "\n"))
  }
}

pub fn summarize(args: String) -> String {
  case json.parse(args, decoder()) {
    Ok(data) -> {
      let replacement_count = list.length(data.replacements)
      case replacement_count {
        1 -> {
          case list.first(data.replacements) {
            Ok(r) -> "(" <> r.path <> ")"
            Error(_) -> "(1 replacement)"
          }
        }
        n -> "(" <> int.to_string(n) <> " replacements)"
      }
    }
    Error(_) -> "(failed to parse args)"
  }
}

pub fn tool() -> client.Tool {
  Function(
    name: "replace_text",
    description: Some(
      "Replace specific text in one or more files. Each replacement finds the first occurrence of old_text and replaces it with new_text. "
      <> "User will be prompted to approve all replacements before they are applied.",
    ),
    parameters: Some(
      json_schema.encode(
        json_schema.object([
          json_schema.field(
            "replacements",
            json_schema.array(
              json_schema.Inline(
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
                      description: Some("File path to modify. Must be relative path in or below current directory."),
                      deprecated: False,
                    ),
                  ),
                  json_schema.field(
                    "old_text",
                    json_schema.String(
                      max_length: None,
                      min_length: None,
                      pattern: None,
                      format: None,
                      nullable: False,
                      title: Some("old_text"),
                      description: Some("Exact text to find and replace (first occurrence only)"),
                      deprecated: False,
                    ),
                  ),
                  json_schema.field(
                    "new_text",
                    json_schema.String(
                      max_length: None,
                      min_length: None,
                      pattern: None,
                      format: None,
                      nullable: False,
                      title: Some("new_text"),
                      description: Some("Text to replace the old text with"),
                      deprecated: False,
                    ),
                  ),
                ])
              )
            )
          ),
        ]),
      ),
    ),
    strict: None,
  )
}
