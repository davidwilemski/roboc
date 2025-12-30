import argv
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import glenvy/env
import glint
import in
import roboc/client
import roboc/context

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
          #(context.User, line),
        ])
      use resp <- result.try(client.send(clnt, new_ctx))
      io.println(client.format_meta_line(resp.meta))
      io.println(resp.message)
      agent_loop(
        clnt,
        context.append(new_ctx, [#(context.Assistant, resp.message)]),
      )
    }
    Error(_) -> {
      Error("")
    }
  }
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
