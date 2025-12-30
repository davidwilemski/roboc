import gleam/list
import gleam/option
import gleam/string

pub type Role {
  User
  Assistant
  System
}

pub type Context {
  Context(lines: List(#(Role, String)))
}

pub fn new() -> Context {
  new_with_system_prompt(option.None)
}

pub fn new_with_system_prompt(system_prompt: option.Option(String)) -> Context {
  let prompt = option.unwrap(system_prompt, default_system_prompt)
  Context([#(System, prompt)])
}

pub fn append(ctx: Context, messages: List(#(Role, String))) -> Context {
  Context(list.append(ctx.lines, messages))
}

pub fn to_string(ctx: Context) -> String {
  string.join(
    list.map(ctx.lines, fn(ln) {
      let #(src, str) = ln
      string.inspect(src) <> ": " <> str
    }),
    "\n",
  )
}

// TODO Improve
const default_system_prompt: String = "You are a programming assistant 
being used to develop software. Assume the user is a moderately 
experienced programmer in the technology you are helping with. 
You are helping them design and build software, not doing it 
for them. Where possible, explain your reasoning unless asked 
otherwise."
