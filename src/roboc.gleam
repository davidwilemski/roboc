import gleam/io
import glint

fn roboc() {
  io.println("Hello from roboc!")
}

pub fn main() -> Nil {
  glint.new()
  |> glint.with_name("roboc")
  |> glint.pretty_help(glint.default_pretty_help())
    |> glint.add(at: [], do: roboc())
}
