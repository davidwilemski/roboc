import gleam/int
import gleam/list
import gleam/option
import gleam/string
import openrouter_client
import openrouter_client/internal
import roboc/format

// wraps openrouter
pub type Client {
  Client(c: openrouter_client.Client)
}

pub type ResponseMetadata {
  ResponseMetadata(provider: String, usage: Usage)
}

pub type Usage {
  Usage(in: Int, out: Int, total: Int)
}

pub type Response {
  Response(message: String, meta: ResponseMetadata)
}

pub type ClientError {
  ClientError(reason: String)
}

pub fn new(key: String) -> Client {
  // TODO allow system prompt
  Client(openrouter_client.new(key, "anthropic/claude-sonnet-4.5", option.None))
}

pub fn send(client: Client, content: String) -> Result(Response, String) {
  let response = openrouter_client.send(client.c, content)
  case response {
    Ok(resp) ->
      Ok(Response(
        string.join(list.map(resp.choices, fn(c) { c.message.content }), "\n"),
        ResponseMetadata(
          resp.provider,
          Usage(
            resp.usage.prompt_tokens,
            resp.usage.completion_tokens,
            resp.usage.total_tokens,
          ),
        ),
      ))
    Error(e) -> Error(openrouter_error_to_string(e))
  }
}

fn openrouter_error_to_string(e: internal.OpenrouterError) -> String {
  case e {
    internal.InvalidApiKey -> "Invalid API Key"
    internal.InvalidResponse -> "Invalid response"
    internal.NoCreditsLeft -> "No credits left"
    internal.HttpRequestError(e) -> "Request error: " <> e
    internal.EmptyResponse -> "Empty response"
    internal.DecodeError(e) ->
      "json response decode error: " <> format.json_decode_error_to_string(e)
    _ -> "unknown error"
  }
}

pub fn format_meta_line(meta: ResponseMetadata) -> String {
  let usage =
    string.join(
      list.map(
        [
          meta.usage.in,
          meta.usage.out,
          meta.usage.total,
        ],
        int.to_string,
      ),
      "/",
    )

  "provider: " <> meta.provider <> " usage (tokens in/out/total): " <> usage
}
