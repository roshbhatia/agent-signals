# The pane record

One record per tmux pane, describing what an agent is doing in it.
`agentstate.go` is the only writer. Every reader is listed below and cites this
file.

Version 1.

## Two encodings, one value

The same fact is published twice over two channels, and neither channel reaches
everywhere.

| | OSC user variable | JSON file |
|---|---|---|
| Where | `agent_state`, set on the pane with OSC 1337 | `<agentPanes>/<pane>.json` |
| Carries | `status`, `reason`, `since`, `agent` | all of those plus identity |
| Encoding | base64 of `status\|reason\|since\|agent` | one JSON object |
| Lifetime | dies with the pane | outlives the pane |
| Liveness rule | none needed | pane existence, see below |
| Fails when | terminal passthrough is unavailable | the pane id is not the writer's |

### OSC passthrough

Measured against `zmx` 0.7.0, which holds terminal state in `libghostty-vt` and
hands the client a grid snapshot: a pane wrapped in `zmx attach` delivers neither
OSC 1337 `SetUserVar` nor OSC 7. A control pane in the same GUI delivered both.
So inside such a wrapper the user variable is not merely stale, it never arrives,
and wezterm reads the wrapper's own cwd rather than the shell's.

Tmux can pass supported OSC sequences to the terminal with passthrough enabled.
The JSON file remains the shared source for status surfaces and pane identity.

Both are rendered from one `state` value in `Run`. `userVar` takes that value
rather than the variables it was built from, so the four shared fields cannot
disagree. A test asserts it.

The user variable is written first, and before the identity lookup, because
that lookup forks git and the variable is the half the owner sees.

## Fields

| Field | Type | Notes |
|---|---|---|
| `version` | number | this schema's version, currently 1 |
| `mux` | number | the tmux server pid, 0 when unknown. See Liveness |
| `pane` | string | tmux pane ID, for example `%3` |
| `session` | string | seshy session name, empty outside one |
| `repo` | string | repository basename |
| `branch` | string | current branch |
| `dirty` | bool | working tree has changes |
| `worktree` | string | absolute path |
| `agent` | string | harness name, a key of the harness registry |
| `status` | string | `working`, `waiting`, or `done` |
| `reason` | string | at most 60 characters, see below |
| `since` | number | unix seconds |

Tmux pane IDs are strings such as `%3`; readers compare them without numeric
coercion.

### `reason` never contains `|`

`tidy` folds `|` to a space. The pipe is the OSC payload's own field separator,
so one inside a reason forges a field. Newlines fold for the same reason on the
file bus.

The rule applies to both encodings even though only the OSC form needs it. The
two are rendered from one value, and a reason that differed between them would
be a second fact.

`reason` is truncated to 60 characters at write time rather than at read time,
so every surface renders the same string.

### `status` has no fourth value

`exit` is an argument to the writer, not a status. It deletes the record.

## Liveness

A record outlives the process that wrote it. `claude`, `atomic`, `pi`, and
`prime-agent` wire `agent-state ... exit`; `codex` and `opencode` do not, so a
crashed or exited one leaves its last record behind.

The rule is pane existence, not an age bound. `since` is republished on every
tool call, so it is a heartbeat only while tool calls happen, and `waiting` and
`done` are turn-terminal. An age bound would expire the two states the deck
exists to show, while a long `working` build kept refreshing. It is not the
writer's pid either: `agent-state` is a one-shot and its pid is dead
microseconds after it publishes.

Every reader already answers pane existence, and each read site says so:

- `ui.lua` walks the panes it is drawing, so a record it never asks for is a
  record it never shows.
- `agent-sessions.sh` reads `tmux list-panes` once per run and prunes against
  it.
- `agent-busy-panes.sh` takes the live pane list from its caller and skips any
  record not in it.

### `mux` is the generation marker

Tmux pane IDs are unique within a server and can be reused after the server
restarts. The pane ID alone cannot distinguish a stale record from a current
one.

`mux` stores the tmux server pid, read with `tmux display-message`; it is 0
outside tmux and in records written before this field existed.

Records with mux 0 remain unverifiable and are reaped rather than read as
current.

The marker is enforced by deletion rather than at read time. `agent-state`
removes the records of any mux that is no longer running, and any record it
cannot attribute to a live mux at all, once per mux. The same pass drops markers
for dead muxes and `.start` files no record claims, skipping the calling pane's
own: `working submit` writes `.start` before it publishes the record the pass
looks for. A `.mux-<pid>` marker file gates the whole pass, so the check costs
one stat on the hot path.
The state directory outlives the mux, so this pass is required to remove stale
records after a server restart.

Doing it by deletion rather than in each reader keeps consumers independent of
the mux process environment.

Tmux server pids separate simultaneous servers, and pane IDs identify
individual panes within each server.

## Readers

| Reader | Reads | Authority |
|---|---|---|
| `wezterm/lua/sysinit/pkg/ui/panes.lua` `agent_state` | both encodings, falling back to the agent-deck plugin | the greater `since`, because either channel can fail to arrive |
| `wezterm/lua/sysinit/pkg/ui/panes.lua` `read_pane_record` | the JSON file, every field | the file, and it is the only source of identity |
| `llm/runtime/agent-sessions.sh` | the JSON file | the file, because it runs outside the pane |
| `llm/runtime/agent-busy-panes.sh` | the JSON file | the file |
| `llm/runtime/agent-review-suffix.sh` | the JSON file | the file |

`agent_state` returns which channel it used as a fifth value. `ui.lua` notifies
only on a `deck` state, because a `record` or `uservar` state means a harness
hook is already firing its own notification for that pane.
