import gleam/dynamic/decode
import gleam/json
import gleam/option
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

pub type Choice {
  Choice(
    logprobs: option.Option(LogProbs),
    finish_reason: String,
    index: Int,
    message: Message,
  )
}

pub type LogProbs {
  LogProbs(content: List(String), refusal: List(String))
}

pub type Message {
  Message(role: String, content: String, refusal: option.Option(String))
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

  let message_decoder = {
    use role <- decode.field("role", decode.string)
    use content <- decode.field("content", decode.string)
    use refusal <- decode.field("refusal", decode.optional(decode.string))
    decode.success(Message(role:, content:, refusal:))
  }

  let choice_decoder = {
    use logprobs <- decode.field("logprobs", decode.optional(logprobs_decoder))
    use finish_reason <- decode.field("finish_reason", decode.string)
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
