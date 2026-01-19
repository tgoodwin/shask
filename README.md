# shask

shask is a wrapper around `llm` that returns a shell command for your request.

## Install llm

`shask` requires `llm`. 

```bash
brew install llm
```

Docs: https://llm.datasette.io/en/stable/  
Install details: https://llm.datasette.io/en/stable/setup.html

## Quick start

```bash
shask "list files by size"
```

## Usage

```bash
shask [--explain|--no-explain] [--raw] [--model MODEL] <question...>
```

By default, `shask` prints a single command to stdout. Use `--raw` to see the
full `llm` response (including `CMD:` / `WHY:` / `NEED_MORE_INFO:` lines).

## Flags

- `--explain`  
  Print the optional short explanation line (if provided).
- `--no-explain`  
  Do not print the explanation line (default).
- `--raw`  
  Output the full raw `llm` response and exit.
- `--model MODEL`  
  Use a specific model for `llm`.

## Examples

Generate a command:

```bash
shask "find large log files in /var/log"
```

Specify a model:

```bash
shask --model gpt-4.1-mini "show top 10 processes by memory"
```

If `shask` needs more info and you are in a TTY, it will prompt you:

```
NEED_MORE_INFO: Which directory should I search?
> /var/log
```

## Troubleshooting

- `llm` must be installed and available in `PATH`.
