import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}
import gleam/result

// originally taken from https://codeberg.org/Cmooon/openrouter_client but modified a good bit (updated to gleam_json v3, made it work against the current API by adding optional/null handling, and more types)

pub type OpenrouterResponse {
  OpenrouterResponse(
    id: String,
    provider: String,
    model: String,
    object: String,
    created: Int,
    choices: List(Choice),
    usage: Usage,
  )
}

pub type FinishReason {
  Stop
  ToolCalls
  Length
  ContentFilter
  ErrorReason
  Unknown(String)
}

pub type Choice {
  Choice(
    logprobs: Option(LogProbs),
    finish_reason: FinishReason,
    index: Int,
    message: Message,
  )
}

pub type LogProbs {
  LogProbs(content: List(String), refusal: List(String))
}

pub type ToolCall {
  FunctionCall(id: String, name: String, arguments: String)
}

pub fn tool_call_to_json(tool_call: ToolCall) -> json.Json {
  let FunctionCall(id:, name:, arguments:) = tool_call
  json.object([
    #("id", json.string(id)),
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", json.string(name)),
        #("arguments", json.string(arguments)),
      ]),
    ),
  ])
}

pub type Message {
  Message(
    role: String,
    content: String,
    refusal: Option(String),
    tool_calls: Option(List(ToolCall)),
    reasoning: Option(String),
  )
}

pub type Usage {
  Usage(prompt_tokens: Int, completion_tokens: Int, total_tokens: Int)
}

// TODO: Parse errors to match them more accurate
pub type OpenrouterError {
  InvalidApiKey
  InvalidResponse
  NoCreditsLeft
  Misc
  HttpRequestError(String)
  EmptyResponse
  DecodeError(json.DecodeError)
}

pub fn decode_openrouter_response(
  json_string: String,
) -> Result(OpenrouterResponse, OpenrouterError) {
  let logprobs_decoder = {
    use content <- decode.optional_field(
      "content",
      [],
      decode.list(decode.string),
    )
    use refusal <- decode.optional_field(
      "refusal",
      [],
      decode.list(decode.string),
    )
    decode.success(LogProbs(content:, refusal:))
  }

  let tool_call_decoder = {
    use t <- decode.field("type", decode.string)
    case t {
      "function" -> {
        use id <- decode.field("id", decode.string)
        use name <- decode.subfield(["function", "name"], decode.string)
        use arguments <- decode.subfield(
          ["function", "arguments"],
          decode.string,
        )
        decode.success(FunctionCall(id:, name:, arguments:))
      }
      _ ->
        decode.failure(
          FunctionCall("", "", ""),
          "unexpected tool call type: " <> t,
        )
    }
  }

  let message_decoder = {
    use role <- decode.field("role", decode.string)
    use content <- decode.field("content", decode.string)
    use refusal <- decode.field("refusal", decode.optional(decode.string))
    use tool_calls <- decode.optional_field(
      "tool_calls",
      None,
      decode.optional(decode.list(tool_call_decoder)),
    )
    use reasoning <- decode.field("reasoning", decode.optional(decode.string))
    // echo reasoning
    decode.success(Message(role:, content:, refusal:, tool_calls:, reasoning:))
  }

  let finish_reason_decoder = {
    use finish_reason_str <- decode.then(decode.string)
    case finish_reason_str {
      "stop" -> decode.success(Stop)
      "tool_calls" -> decode.success(ToolCalls)
      "length" -> decode.success(Length)
      "content_filter" -> decode.success(ContentFilter)
      "error" -> decode.success(ErrorReason)
      _ -> decode.success(Unknown(finish_reason_str))
    }
  }

  let choice_decoder = {
    use logprobs <- decode.field("logprobs", decode.optional(logprobs_decoder))
    use finish_reason <- decode.field("finish_reason", finish_reason_decoder)
    use index <- decode.field("index", decode.int)
    use message <- decode.field("message", message_decoder)
    decode.success(Choice(logprobs:, finish_reason:, index:, message:))
  }

  let usage_decoder = {
    use prompt_tokens <- decode.field("prompt_tokens", decode.int)
    use completion_tokens <- decode.field("completion_tokens", decode.int)
    use total_tokens <- decode.field("total_tokens", decode.int)
    decode.success(Usage(prompt_tokens:, completion_tokens:, total_tokens:))
  }

  let decoder = {
    use id <- decode.field("id", decode.string)
    use provider <- decode.field("provider", decode.string)
    use model <- decode.field("model", decode.string)
    use object <- decode.field("object", decode.string)
    use created <- decode.field("created", decode.int)
    use choices <- decode.field("choices", decode.list(choice_decoder))
    use usage <- decode.field("usage", usage_decoder)
    decode.success(OpenrouterResponse(
      id:,
      provider:,
      model:,
      object:,
      created:,
      choices:,
      usage:,
    ))
  }

  json.parse(from: json_string, using: decoder)
  |> result.map_error(fn(e) { DecodeError(e) })
}
