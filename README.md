# agent-signals

Publish pane status from agent hooks. Read the same status from terminal surfaces and command runners.

```sh
go install github.com/roshbhatia/agent-signals/cmd/agent-state@latest
agent-state claude working tool < hook.json
agent-state claude waiting 'needs approval' </dev/null
agent-state claude done </dev/null
agent-state claude exit </dev/null
# Nix
nix run github:roshbhatia/agent-signals -- claude working
```

`WEZTERM_PANE` identifies the pane. Without it, the writer exits successfully without writing state.
State records use atomic replacement and the existing XDG agent paths. The optional sysinit paths manifest remains supported.
See [the schema](state/SCHEMA.md) for fields and OSC 1337 user variables.
Go consumers can import `github.com/roshbhatia/agent-signals/state` (package `agentstate`).

This package owns status transport and notification adapters. Producers own status decisions.
Orc owns session orchestration, assignments, and checkpoints. This package neither schedules work nor changes Orc sessions.
The package works without Orc or sysinit.

## Notifications

```sh
nix run github:roshbhatia/agent-signals#notifier -- claude approval </dev/null
```

The macOS adapter uses `alerter`. It exits without a notification when that command is unavailable.
It classifies hook messages, groups notifications, and limits repeated idle notifications.
Optional icons live under `$XDG_DATA_HOME/agent-notify/icons` (default `~/.local/share`).
`lib.mkNotifier { inherit pkgs; labels = "..."; }` accepts an optional `agent_label` shell function.
Personal icons, harness registration, and hook installation belong to the caller.

`lib.mkNotifier { inherit pkgs; settings = { ... }; }` merges caller settings with
[the defaults](nix/notification-defaults.nix). The build validates the result against
[`agent-notify/v1`](schemas/notification-config.schema.json). The returned package
exposes `configFile` and `schema` for inspection or installation.

Policy layers merge in order: defaults, event, profile defaults, profile event.
`AGENT_NOTIFY_PROFILE=prompt` selects a 300-second approval notification with a
content image. Other events retain their normal settings. Profiles do not change
classification, pane identity, grouping, or click-to-focus behavior.

```nix
settings = {
  events.done.minDurationSeconds = 30;
  events.idle.cooldownSeconds = 600;
  events.approval.sound = null;
  agents.pi = { label = "Pi"; icon = "${myIcons}/pi.png"; };
  defaultIcon = "${myIcons}/agent.png";
};
```

An event can set `enabled = false`. A null sound is silent. Missing icons fall back
to `defaultIcon`, then the XDG generic icon; absent files are omitted from delivery.
Legacy `AGENT_NOTIFY_TIMEOUT_*` overrides remain supported. Hook stdin remains a
harness payload with optional `cwd`, `message`, and `notification_type`; it is
separate from the configuration schema and the pane-state schema.

The `runtime` directory also exposes shell fragments for pane identity and focus adapters.

```sh
nix develop -c go test ./...
nix build .#checks.aarch64-darwin.package .#notifier
```

Extracted from [sysinit](https://github.com/roshbhatia/sysinit/tree/6b71b078a36964ab3610c24af7c76b179ce667e7). MIT licensed.
