import copy
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time

import jsonschema

runtime, schema_path, defaults_path = map(Path, sys.argv[1:])
schema = json.loads(schema_path.read_text())
defaults = json.loads(defaults_path.read_text())
jsonschema.Draft202012Validator.check_schema(schema)
jsonschema.validate(defaults, schema)
for key, value in [
    ("timeoutSeconds", 0),
    ("cooldownSeconds", -1),
    ("enabled", "yes"),
    ("unknown", 1),
]:
    invalid = copy.deepcopy(defaults)
    invalid["defaults"][key] = value
    try:
        jsonschema.validate(invalid, schema)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError(f"Accepted invalid policy: {key}")

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "bin").mkdir()
    output = root / "notification.json"
    alerter = root / "bin/alerter"
    alerter.write_text(
        "#!"
        + sys.executable
        + "\n"
        + """import json,os,sys
from pathlib import Path
p=Path(os.environ['NOTIFY_TEST_OUTPUT'])
tmp=p.with_suffix('.tmp')
tmp.write_text(json.dumps(sys.argv[1:]))
tmp.replace(p)
print('@CONTENTCLICKED')
"""
    )
    alerter.chmod(0o700)
    wezterm = root / "bin/wezterm"
    wezterm.write_text(
        '#!/bin/sh\n[ "$1" = cli ] && [ "$2" = --no-auto-start ] || exit 2\nprintf "[]"\n'
    )
    wezterm.chmod(0o700)
    focus = root / "bin/focus"
    focus.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$NOTIFY_TEST_FOCUS"\n')
    focus.chmod(0o700)
    config_path = root / "config.json"
    script = root / "notify.sh"
    fragments = [
        "paths.sh",
        "agent-group.sh",
        "agent-review-suffix.sh",
        "agent-identity.sh",
        "agent-classify.sh",
    ]
    script.write_text(
        "\n".join((runtime / name).read_text() for name in fragments)
        + '\nagent_label() { printf "%s" "$1"; }\nnotify_config='
        + shlex.quote(str(config_path))
        + "\n"
        + (runtime / "agent-notify.sh").read_text()
    )
    env = os.environ | {
        "PATH": str(root / "bin") + ":" + os.environ["PATH"],
        "HOME": str(root),
        "XDG_STATE_HOME": str(root / "state"),
        "XDG_DATA_HOME": str(root / "data"),
        "NOTIFY_TEST_OUTPUT": str(output),
        "NOTIFY_TEST_FOCUS": str(root / "focus"),
    }
    env.pop("WEZTERM_PANE", None)
    env.pop("AGENT_NOTIFY_PROFILE", None)
    config = copy.deepcopy(defaults)
    icon = root / "fixture.png"
    icon.touch()
    config["agents"]["test"] = {"label": "Test Agent", "icon": str(icon)}
    config_path.write_text(json.dumps(config))

    def run(reason, payload=None, extra=None, expected=True):
        output.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", str(script), "test", reason, str(focus)],
            input=json.dumps(payload or {}),
            text=True,
            capture_output=True,
            env=env | (extra or {}),
            cwd=root,
        )
        assert result.returncode == 0, result.stderr
        for _ in range(60 if expected else 10):
            if output.exists():
                break
            time.sleep(0.02)
        assert output.exists() == expected, (reason, result.stderr)
        return json.loads(output.read_text()) if expected else []

    args = run("approval", {"message": "Review this"})
    assert args[args.index("--title") + 1] == "Test Agent · needs your approval"
    assert args[args.index("--message") + 1] == "Review this"
    assert args[args.index("--timeout") + 1] == "5"
    assert args[args.index("--app-icon") + 1] == str(icon)
    args = run(
        "approval", extra={"AGENT_NOTIFY_PROFILE": "prompt", "WEZTERM_PANE": "71"}
    )
    assert args[args.index("--timeout") + 1] == "300"
    assert "--content-image" in args
    args = run("attention", {"notification_type": "permission_prompt"})
    assert "approval" in args[args.index("--title") + 1]
    run("attention", {"notification_type": "auth_success"}, expected=False)
    run("attention", {"message": "not classified"}, expected=False)
    run("idle")
    run("idle", expected=False)
    panes = root / "state/agents/panes"
    panes.mkdir(parents=True)
    (panes / "71.start").write_text(str(int(time.time())))
    run("done", extra={"WEZTERM_PANE": "71"}, expected=False)
    (panes / "71.start").write_text(str(int(time.time()) - 120))
    run("done", extra={"WEZTERM_PANE": "71"})
    config["events"]["approval"]["sound"] = None
    config_path.write_text(json.dumps(config))
    assert "--sound" not in run("approval")
    config["events"]["approval"]["enabled"] = False
    config_path.write_text(json.dumps(config))
    run("approval", expected=False)
    config["events"]["approval"]["enabled"] = True
    config["agents"]["test"]["icon"] = str(root / "missing.png")
    config_path.write_text(json.dumps(config))
    assert "--app-icon" not in run("approval")
    args = run("approval", extra={"AGENT_NOTIFY_TIMEOUT_APPROVAL": "12"})
    assert args[args.index("--timeout") + 1] == "12"
    for _ in range(50):
        if (root / "focus").exists():
            break
        time.sleep(0.02)
    assert (root / "focus").exists()
print(
    "Notification schema, profiles, classification, assets, throttling, focus and legacy overrides passed"
)
