import gleam/function
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import roboc/context
import roboc/openrouter/types

pub type Client {
  Client(api_key: String, model: String, tools: List(Tool))
}

pub type Tool {
  /// defines a function call tool
  /// name is <= 64 chars
  Function(
    name: String,
    description: option.Option(String),
    /// should be an object at the outer layer
    parameters: Option(json.Json),
    strict: option.Option(Bool),
  )
}

pub fn new(api_key: String, model: String, tools: List(Tool)) -> Client {
  Client(api_key, model, tools)
}

pub fn chat(
  client: Client,
  messages: List(context.Message),
) -> Result(types.OpenrouterResponse, types.OpenrouterError) {
  let tool_choice = case list.length(client.tools) {
    0 -> json.null()
    _ -> json.string("auto")
  }

  // Build the JSON body
  let body =
    json.object([
      #("model", json.string(client.model)),
      #("messages", json.array(messages, encode_message)),
      #("tool_choice", tool_choice),
      #("tools", json.array(client.tools, encode_tool)),
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

fn encode_message(message: context.Message) -> json.Json {
  let common_fields = [
    #("content", json.string(message.content)),
  ]
  let specialized_fields = case message {
    context.UserMsg(_) -> [#("role", json.string("user"))]
    context.SystemMsg(_) -> [#("role", json.string("system"))]
    context.AssistantMsg(_, Some(tool_calls)) -> {
      [
        #("role", json.string("assistant")),
        #("tool_calls", json.array(tool_calls, types.tool_call_to_json)),
      ]
    }
    context.AssistantMsg(_, None) -> []
    context.ToolRespMsg(_, tool_call_id) -> [
      #("role", json.string("tool")),
      #("tool_call_id", json.string(tool_call_id)),
    ]
  }
  json.object(list.append(common_fields, specialized_fields))
}

fn encode_tool(tool: Tool) -> json.Json {
  case tool {
    Function(..) -> {
      json.object([
        #("type", json.string("function")),
        #(
          "function",
          json.object([
            #("name", json.string(tool.name)),
            #("description", json.nullable(tool.description, json.string)),
            #("parameters", json.nullable(tool.parameters, function.identity)),
            #("strict", json.nullable(tool.strict, json.bool)),
          ]),
        ),
      ])
    }
  }
}
