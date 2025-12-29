import argv
import gleam/io
import glint

fn roboc() -> glint.Command(Nil) {
  use <- glint.command_help("Runs basic roboc agent")
  use _, _, _ <- glint.command()

  io.println("Hello from roboc!")
}

pub fn main() -> Nil {
  glint.new()
  |> glint.with_name("roboc")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: roboc())
  |> glint.run(argv.load().arguments)
}
