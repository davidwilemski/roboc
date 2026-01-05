import child_process
import gleam/result
import gleam/string
import simplifile
import temporary

/// Generate a unified diff between old and new content using git diff
pub fn unified_diff(
  old_content: String,
  new_content: String,
) -> Result(String, String) {
  temporary.create(temporary.directory(), fn(temp_dir) {
    let old_file = temp_dir <> "/roboc_diff_old.tmp"
    let new_file = temp_dir <> "/roboc_diff_new.tmp"
    use _ <- result.try(
      simplifile.write(old_file, old_content)
      |> result.map_error(fn(_) { "Failed to write temp file" }),
    )
    use _ <- result.try(
      simplifile.write(new_file, new_content)
      |> result.map_error(fn(_) { "Failed to write temp file" }),
    )
    let args = [
      "diff", "--no-index", "--no-color", "--unified=3", old_file, new_file,
    ]

    let result =
      child_process.new_with_path("git")
      |> child_process.args(args)
      |> child_process.run

    case result {
      Ok(output) -> {
        // git diff returns exit code 1 when there are differences, 0 when identical
        // We want the stdout in either case
        Ok(output.output)
      }
      Error(e) ->
        Error(
          "git diff failed - is git installed?. Error: " <> string.inspect(e),
        )
    }
  })
  |> result.map_error(string.inspect)
  |> result.flatten
}
