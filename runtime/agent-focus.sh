pane=${1:-}
session=${2:-}

tmux=$(command -v tmux 2> /dev/null || true)
notifier=$(command -v alerter 2> /dev/null || true)

if [ -n "$notifier" ] && [ -n "$pane" ]; then
  "$notifier" --remove "$(agent_group "" "" "$pane")" > /dev/null 2>&1 || true
fi

raise_app() {
  /usr/bin/osascript -e 'tell application "WezTerm" to activate' 2> /dev/null || true
}

[ -n "$tmux" ] || {
  raise_app
  exit 0
}

if [ -n "$pane" ] && [ -n "$tmux" ]; then
  target=$($tmux display-message -p -t "$pane" '#{session_name}:#{window_index}' 2> /dev/null || true)
  if [ -n "$target" ] && $tmux switch-client -t "$target" 2> /dev/null && $tmux select-pane -t "$pane" 2> /dev/null; then
    raise_app
    exit 0
  fi
fi

if [ -n "$session" ] && [ -n "$tmux" ]; then
  if $tmux has-session -t "$session" 2> /dev/null && $tmux switch-client -t "$session" 2> /dev/null; then
    raise_app
    exit 0
  fi
fi

raise_app
exit 0
