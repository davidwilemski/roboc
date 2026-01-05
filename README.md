# roboc

A just for fun personal LLM coding agent

**Note: This isn't intended for widespread use. I [developed it for fun as a first Gleam project and to experiment with the LLM APIs](https://www.davidwilemski.com/what-i-learned-from-writing-a-basic-coding-agent). It's not meant to be "production grade" and while I was cautious about destructive operations, I make no guarantees on its safety or operation.**

## Features

A small CLI coding agent, providing:

- optional model selection (uses OpenRouter's API), defaulting to `anthropic/claude-sonnet-4.5`
- basic tools (file search, file reading/grepping, file writing)
  - basic safety mechanisms on these tools: checking for directory traversal, approval prompt on edits
- token counts on each message

## Use

Requires an OpenRouter API key to be present in the `ROBOC_API_KEY` environment
variable. Provide an alternate model selection with the `--model` flag.

Start the tool in the directory you want to work in.

```sh
$ roboc --help
Runs basic roboc agent

USAGE:
    roboc [ ARGS ] [ --model=<STRING> ]

FLAGS:
    --help                Print help information

    --model=<STRING>      Which model to use on the provider. Defaults to
                          anthropic/claude-sonnet-4.5.
```
## Known issues

- Sometimes the agent seems to get stuck in a "loop", repeating a previous message phrased in a slightly similar way
- Patch application is fairly unreliable right now, mostly in terms of the patches not applying at all due to malformed patch generation but other issues could arise too. Be careful!
- Other things potentially documented in TODO.txt

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
