import argv
import gleam/io
import gleam/result
import glenvy/env
import glint

fn build_openrouter() -> Result(String, env.Error) {
  todo
}

fn get_api_key() -> Result(String, String) {
  result.map_error(env.string("ROBOC_API_KEY"), fn(e) {
    case e {
      env.NotFound(s) -> "Environment variable not found: " <> s
      env.FailedToParse(s) -> "Error parsing env var: " <> s
    }
  })
}

fn roboc() -> glint.Command(Nil) {
  use <- glint.command_help("Runs basic roboc agent")
  use _, _, _ <- glint.command()

  case get_api_key() {
    Ok(key) -> {
      io.println("Hello from roboc!")
      io.println("api key: " <> key)
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
