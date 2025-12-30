import gleam/int
import gleam/list
import gleam/string
import roboc/context
import roboc/format
import roboc/openrouter/client
import roboc/openrouter/types

// wraps openrouter
pub type Client {
  Client(client: client.Client)
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
  Client(client.new(key, "anthropic/claude-sonnet-4.5"))
}

pub fn send(client: Client, ctx: context.Context) -> Result(Response, String) {
  let messages = ctx_to_messages(ctx)
  let response = client.chat(client.client, messages)
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

fn openrouter_error_to_string(e: types.OpenrouterError) -> String {
  case e {
    types.InvalidApiKey -> "Invalid API Key"
    types.InvalidResponse -> "Invalid response"
    types.NoCreditsLeft -> "No credits left"
    types.HttpRequestError(e) -> "Request error: " <> e
    types.EmptyResponse -> "Empty response"
    types.DecodeError(e) ->
      "json response decode error: " <> format.json_decode_error_to_string(e)
    _ -> "unknown error"
  }
}

fn ctx_to_messages(ctx: context.Context) -> List(client.RequestMessage) {
  ctx.lines
  |> list.map(fn(l) {
    let #(r, m) = l
    client.RequestMessage(role_to_string(r), m)
  })
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

pub fn role_to_string(role: context.Role) -> String {
  role |> string.inspect |> string.lowercase
}
