import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result
import roboc/openrouter/types

pub type Client {
  Client(api_key: String, model: String)
}

pub type RequestMessage {
  RequestMessage(role: String, content: String)
}

pub fn new(api_key: String, model: String) -> Client {
  Client(api_key, model)
}

pub fn chat(
  client: Client,
  messages: List(RequestMessage),
) -> Result(types.OpenrouterResponse, types.OpenrouterError) {
  // Build the JSON body
  let body =
    json.object([
      #("model", json.string(client.model)),
      #("messages", json.array(messages, encode_message)),
    ])
    |> json.to_string

  // Create and send the request
  request.new()
  |> request.set_method(http.Post)
  |> request.set_host("openrouter.ai")
  |> request.set_path("/api/v1/chat/completions")
  |> request.set_header("authorization", "Bearer " <> client.api_key)
  |> request.set_header("content-type", "application/json")
  |> request.set_body(body)
  |> httpc.send
  // TODO handle https://hexdocs.pm/gleam_httpc/gleam/httpc.html#HttpError
  |> result.map_error(fn(_) { types.HttpRequestError("error making request") })
  |> result.try(fn(response) { types.decode_openrouter_response(response.body) })
}

fn encode_message(message: RequestMessage) -> json.Json {
  json.object([
    #("role", json.string(message.role)),
    #("content", json.string(message.content)),
  ])
}
