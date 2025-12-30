import argv
import gleam/int
import gleam/io
import gleam/result
import glenvy/env
import glint
import roboc/client

fn roboc() -> glint.Command(Nil) {
  use <- glint.command_help("Runs basic roboc agent")
  use _, _, _ <- glint.command()

  case get_api_key() {
    Ok(key) -> {
      let client = client.new(key)
      io.println("Hello from roboc!")
      let response =
        client.send(
          client,
          "Hi Claude, please respond with a random programming language's basic print function with the text 'Hello, from roboc'",
        )
      case response {
        Ok(resp) -> {
          io.println("provider: " <> resp.meta.provider)
          io.println(
            "usage (tokens): " <> int.to_string(resp.meta.total_tokens),
          )
          io.println(resp.message)
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
