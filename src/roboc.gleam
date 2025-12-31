import argv
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import glenvy/env
import glint
import in
import roboc/client
import roboc/context.{AssistantMsg, UserMsg}
import roboc/openrouter/types
import roboc/tools

// returns both the agent's response + the context (with the response appended)
fn agent_loop(
  clnt: client.Client,
  ctx: context.Context,
) -> Result(#(String, context.Context), String) {
  io.print_error(">>> ")
  case read_lines() {
    Ok(line) -> {
      let new_ctx =
        context.append(ctx, [
          UserMsg(line),
        ])
      use resp <- result.try(client.send(clnt, new_ctx))
      io.println(client.format_meta_line(resp.meta))
      io.println(resp.message)
      let tool_calls = case list.length(resp.tool_calls) {
        0 -> None
        _ -> Some(resp.tool_calls)
      }
      let message = AssistantMsg(resp.message, tool_calls)
      let agent_updated_context = context.append(new_ctx, [message])

      case tool_calls {
        None -> agent_loop(clnt, agent_updated_context)
        Some(calls) -> {
          use after_tools_ctx <- result.try(tools_loop(
            clnt,
            agent_updated_context,
            calls,
          ))
          agent_loop(clnt, after_tools_ctx)
        }
      }
    }
    Error(_) -> {
      Error("")
    }
  }
}

fn tools_loop(
  clnt: client.Client,
  ctx: context.Context,
  tool_calls: List(types.ToolCall),
) -> Result(context.Context, String) {
  let tool_call_results = handle_tool_calls(tool_calls)
  let after_tool_ctx = context.append(ctx, tool_call_results)
  // call llm again with tool results
  use resp <- result.try(client.send(clnt, after_tool_ctx))
  io.println(client.format_meta_line(resp.meta))
  io.println(resp.message)

  let tool_calls = case list.is_empty(resp.tool_calls) {
    True -> None
    False -> Some(resp.tool_calls)
  }
  let message = AssistantMsg(resp.message, tool_calls)
  let agent_updated_context = context.append(after_tool_ctx, [message])

  case list.is_empty(resp.tool_calls) {
    // No more tools calls, we can return context and continue
    True -> {
      Ok(agent_updated_context)
    }
    // There's some more tool calls as follow up, recurse
    False -> {
      // Recurse on new tool calls
      tools_loop(clnt, agent_updated_context, resp.tool_calls)
    }
  }
}

// for each tool call identify the matching tool, if any, and call the handler for it. Build a ToolCallMsg in response
fn handle_tool_calls(tool_calls: List(types.ToolCall)) -> List(context.Message) {
  list.map(tool_calls, fn(t) {
    io.println_error(
      "calling tool: " <> t.name <> " with args: " <> t.arguments,
    )
    let content = case tools.handle_tool(t) {
      Ok(c) -> {
        io.println_error("tool call output :")
        string.split(c, "\n")
        |> list.take(15)
        |> string.join("\n")
        |> io.print_error
        c
      }
      Error(e) -> {
        io.println_error("Error in tool call: " <> e)
        "Error in tool call: " <> e
      }
    }
    context.ToolRespMsg(content:, tool_call_id: t.id)
  })
}

fn roboc() -> glint.Command(Nil) {
  use <- glint.command_help("Runs basic roboc agent")
  use _, _, _ <- glint.command()

  case get_api_key() {
    Ok(key) -> {
      io.println("Hello from roboc!")

      let client = client.new(key)
      let init_ctx = context.new()

      case agent_loop(client, init_ctx) {
        Ok(#(msg, _)) -> {
          // print last response
          io.println(msg)
          io.println("Ending session!")
        }
        Error(e) -> io.println(e)
      }
    }
    Error(s) -> io.print_error(s)
  }
}

pub fn main() -> Nil {
  glint.new()
  |> glint.with_name("roboc")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: roboc())
  |> glint.run(argv.load().arguments)
}

fn get_api_key() -> Result(String, String) {
  result.map_error(env.string("ROBOC_API_KEY"), fn(e) {
    case e {
      env.NotFound(s) -> "Environment variable not found: " <> s
      env.FailedToParse(s) -> "Error parsing env var: " <> s
    }
  })
}

fn read_lines() -> Result(String, String) {
  use lines <- result.map(read_lines_internal([]))
  lines |> string.join("\n")
}

fn read_lines_internal(lines: List(String)) -> Result(List(String), String) {
  case in.read_line() {
    Ok(line) if line == "\n" -> Ok(lines)
    Ok(line) -> read_lines_internal(list.append(lines, [line]))
    Error(e) -> Error(string.inspect(e))
  }
}
