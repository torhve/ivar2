# ivar2

Luajit IRC/Matrix/Slack/Zulip bot. Async I/O via `cqueues`. Modules can be `.lua` or `.moon` (MoonScript, loaded at runtime if `moonscript` is installed).

## Entrypoints

- `lua ivar2.lua <config.lua>` — IRC
- `lua matrix.lua <config.lua>` — Matrix
- `lua slack.lua <config.lua>` — Slack
- `lua zulip.lua <config.lua>` — Zulip

All share the same `package.path`: `libs/?.lua;libs/?/init.lua;`.

## Commands

- **Test**: `busted` (all) or `busted spec/foo_spec.lua` (single). Helper: `spec/helper.lua` provides `assert_loop(cq, timeout)` and `TEST_TIMEOUT=1`. Discovery: ROOT is `spec` + `modules`, pattern `_spec` — spec files must be named `*_spec.lua`/`*_spec.moon`.
  - Dir-module specs live inside the module dir: `modules/<name>/<name>_spec.lua` (single-spec run: `busted modules/<name>/<name>_spec.lua`).
  - Flat single-file modules keep `spec/modules/<name>_spec.lua`.
- **Lint**: `luacheck .` (Lua 5.1 std, globals: `ivar2`, `say`, `reply`, `setfenv`, `unused_args: false`).
- **Module dev**: `lua tools/test_module.lua <module> <message>` — test a single module's pattern matching and output without running the full bot. Use `--list` to show available patterns. Options: `--config`, `--timeout`, `--dest`, `--nick`.

## Remote Control (FIFO)

FIFO-based remote control is available on all backends. A FIFO is created at startup in the working directory, named after the config file with its extension stripped (e.g., `config/ivartest.lua` produces a FIFO named `ivartest`).

Send commands via shell redirection: `echo "command arg" > <fifo_name>`

| Command | Description |
|---------|-------------|
| `> lua_code` | Execute arbitrary Lua code (has `ivar2` in env) |
| `quit [msg]` | Quit the bot |
| `join #chan [pass]` | Join a channel |
| `part #chan` | Leave a channel |
| `topic #chan new topic` | Set channel topic |
| `mode dest mode` | Change mode |
| `kick #chan user [reason]` | Kick a user |
| `nick newnick` | Change nick |
| `ignore mask` | Ignore a mask |
| `unignore mask` | Unignore a mask |
| `loadmodule name` | Load a module |
| `disablemodule name` | Disable a module |
| `reloadmodule name` | Disable then reload a module |
| `reload` | Full reload (SIGHUP equivalent) |

## Hot Reloading Workflow

After making code changes to a module or core file:

1. Run `busted` to confirm tests pass
2. Reload the module on the running bot without restarting:
   ```
   echo "reloadmodule <name>" > <fifo_name>
   ```
3. For infrastructure changes (backends, core modules), use a full reload instead:
   ```
   echo "reload" > <fifo_name>
   ```

After completing code changes that pass tests, offer to reload the affected module on the running bot using the FIFO command above. DO NOT test the module using the fif.

## Module Pattern

Modules return a table keyed by event name (usually `PRIVMSG`). Keys are Lua patterns; `%p` gets replaced by the configured command prefix. `say()` and `reply()` are injected into the module environment — call them without `self:` prefix.

```lua
return {
    PRIVMSG = {
        ['^%pping$'] = function(self, source, destination)
            say('pong!')
        end,
    },
}
```

## Key Paths

| Path | Purpose |
|------|---------|
| `libs/` | Shared libraries (irc, util, persist, event, logging, simplehttp, spark, uriparse) |
| `modules/` | Bot modules (~118 files, `.lua` or `.moon`) |
| `core/` | Infrastructure (ircevents, webserver, x0, slack_api, zulip) |
| `cache/` | Runtime SQLite data (gitignored) |
| `config/*` | Config files (gitignored) |
| `bot-*.lua` | Generated bot files (gitignored) |

## Editor

`.editorconfig`: tabs, `indent_size: 2` for `*.{lua,moon}`, LF line endings, no final newline.

## MoonScript

- **Reference**: <https://moonscript.org/reference/> — consult for syntax questions.
- **Syntax**: indentation-based, no `end`/`do` keywords. 2-space indent per `.editorconfig`.
- **Compile check**: `moonc -o /dev/null modules/foo.moon` validates syntax. Plain `moonc foo.moon` writes a stray `foo.lua` next to the source — always use `-o /dev/null` (or `-o` to a temp/scratch dir).
- **Table literals**: use `:` for key-value pairs, e.g. `{enabled: false, last_scores: {}}`.
- **Function calls**: space-separated args (`func a, b`) or `obj\method "arg"` for chained calls.
- **String interpolation**: `"#{expr}"` — double quotes only.
- **Control flow**: `if/else if/else` without `end`; `continue`/`break` work in loops.
- **Discarding return values**: use `_` variable, not trailing comma (e.g. `a, _ = func()`).
- **Chained calls on array elements**: extract to variable first (`x = arr[#arr]; x:method()`).
- **Never mix Lua `end` blocks into `.moon` files** — `moonc` will reject them.

## Framework Quirks

- No package manifest — deps installed via luarocks/hererocks (see README)
- Signal handling: `SIGHUP` reloads modules, `SIGTERM`/`SIGINT` quit. FIFO-based remote control (see "Remote Control") provides the same functionality via shell.
- Optional webserver on port 9000 (configured in config file)
- `ivar2` global table holds bot instance; modules access it directly
- `libs/event.lua` provides `Register`, `Fire`, `ClearModule`, `ClearAll` for cross-module events
