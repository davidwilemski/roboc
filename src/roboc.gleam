import gleam/int
import gleam/string
import gleam/list
import argv
import gleam/io
import gleam/json
import gleam/dynamic/decode
import gleam/option
import gleam/result
import glenvy/env
import glint
import openrouter_client
import openrouter_client/internal

fn roboc() -> glint.Command(Nil) {
  use <- glint.command_help("Runs basic roboc agent")
  use _, _, _ <- glint.command()

  case build_openrouter_client() {
    Ok(client) -> {
      io.println("Hello from roboc!")
      let response = openrouter_client.send(client, "Hi Claude, please respond with a random programming language's basic print function with the text 'Hello, from roboc'")
      case response {
        Ok(resp) -> {
          io.println("provider: " <> resp.provider)
          io.println("usage (tokens): " <> int.to_string(resp.usage.total_tokens))
          io.println(string.join(list.map(resp.choices, fn(c) { c.message.content }), "\n"))
        }
        Error(e) -> io.println(openrouter_error_to_string(e))
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

fn build_openrouter_client() -> Result(openrouter_client.Client, String) {
  use key <- result.map(get_api_key())
  // TODO allow system prompt
  openrouter_client.new(key, "anthropic/claude-sonnet-4.5", option.None)
}

fn get_api_key() -> Result(String, String) {
  result.map_error(env.string("ROBOC_API_KEY"), fn(e) {
    case e {
      env.NotFound(s) -> "Environment variable not found: " <> s
      env.FailedToParse(s) -> "Error parsing env var: " <> s
    }
  })
}

fn openrouter_error_to_string(e: internal.OpenrouterError) -> String {
  case e {
    internal.InvalidApiKey -> "Invalid API Key"
    internal.InvalidResponse -> "Invalid response"
    internal.NoCreditsLeft -> "No credits left"
    internal.HttpRequestError(e) -> "Request error: " <> e
    internal.EmptyResponse -> "Empty response"
    internal.DecodeError(e) -> "json response decode error: " <> json_decode_error_to_string(e)
    _ -> "unknown error"
  }
}

fn json_decode_error_to_string(e: json.DecodeError) -> String {
  case e {
    json.UnexpectedEndOfInput -> "UnexpectedEndOfInput"
    json.UnexpectedByte(b) -> "UnexpectedByte: " <> b
    json.UnexpectedSequence(s) -> "Unexpected Sequence: " <> s
    json.UnableToDecode(errs) -> string.join(list.map(errs, format_decode_error), "\n")
  }
}

fn format_decode_error(e: decode.DecodeError) -> String {
  "DecodeError(expected: " <> e.expected <> ", found: " <> e.found <> " path: " <> string.join(e.path, "/") <> ")"
}
