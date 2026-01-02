import gleam/int
import gleam/list
import gleam/option
import gleam/string
import roboc/context
import roboc/format
import roboc/openrouter/client
import roboc/openrouter/types
import roboc/tools

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
  Response(
    message: String,
    tool_calls: List(types.ToolCall),
    meta: ResponseMetadata,
  )
}

pub type ClientError {
  ClientError(reason: String)
}

pub fn new(key: String, model: String) -> Client {
  // TODO allow system prompt
  Client(client.new(key, model, tools.all_tools()))
}

pub fn send(client: Client, ctx: context.Context) -> Result(Response, String) {
  let response = client.chat(client.client, ctx.lines)
  case response {
    Ok(resp) -> {
      let tool_calls =
        list.filter(resp.choices, fn(c) { c.finish_reason == types.ToolCalls })
        |> list.flat_map(fn(c) { option.unwrap(c.message.tool_calls, []) })
      Ok(Response(
        string.join(list.map(resp.choices, fn(c) { c.message.content }), "\n"),
        tool_calls,
        ResponseMetadata(
          resp.provider,
          Usage(
            resp.usage.prompt_tokens,
            resp.usage.completion_tokens,
            resp.usage.total_tokens,
          ),
        ),
      ))
    }
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
