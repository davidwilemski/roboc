import gleam/list
import gleam/option
import roboc/openrouter/types

pub type Message {
  UserMsg(content: String)
  AssistantMsg(content: String, tool_calls: option.Option(List(types.ToolCall)))
  SystemMsg(content: String)
  ToolRespMsg(content: String, tool_call_id: String)
}

pub type Context {
  Context(lines: List(Message))
}

pub fn new() -> Context {
  new_with_system_prompt(option.None)
}

pub fn new_with_system_prompt(system_prompt: option.Option(String)) -> Context {
  let prompt = option.unwrap(system_prompt, default_system_prompt)
  Context([SystemMsg(prompt)])
}

pub fn append(ctx: Context, messages: List(Message)) -> Context {
  Context(list.append(ctx.lines, messages))
}

// TODO Improve
const default_system_prompt: String = "You are a programming assistant 
being used to develop software. Assume the user is a moderately 
experienced programmer in the technology you are helping with. 
You are helping them design and build software, not doing it 
for them. Where possible, explain your reasoning unless asked 
otherwise."
