import roboc/openrouter/client.{type Tool}
import roboc/openrouter/types
import roboc/tools/find_files
import roboc/tools/grep_files
import roboc/tools/read_files
import roboc/tools/replace_text
import roboc/tools/write_file

pub fn handle_tool(tool: types.ToolCall) -> Result(String, String) {
  case tool.name {
    "find_files" -> find_files.handle(tool.arguments)
    "grep_files" -> grep_files.handle(tool.arguments)
    "read_files" -> read_files.handle(tool.arguments)
    "write_file" -> write_file.handle(tool.arguments)
    "replace_text" -> replace_text.handle(tool.arguments)
    _ -> Error("unknown tool name")
  }
}

/// Summarize tool call arguments for logging
/// Shows useful info without dumping large content
pub fn summarize_tool_call(tool_name: String, args: String) -> String {
  case tool_name {
    "write_file" -> write_file.summarize(args)
    "replace_text" -> replace_text.summarize(args)
    "read_files" -> read_files.summarize(args)
    "grep_files" | "find_files" -> {
      // These typically have small args, show them
      "with args: " <> args
    }
    _ -> "with args: " <> args
  }
}

pub fn all_tools() -> List(Tool) {
  [
    find_files.tool(),
    grep_files.tool(),
    read_files.tool(),
    write_file.tool(),
    replace_text.tool(),
  ]
}
