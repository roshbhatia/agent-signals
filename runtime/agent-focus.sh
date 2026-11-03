pane=${1:-}
session=${2:-}

wz=$(command -v wezterm 2> /dev/null || true)
notifier=$(command -v alerter 2> /dev/null || true)

if [ -n "$notifier" ] && [ -n "$pane" ]; then
  "$notifier" --remove "$(agent_group "" "" "$pane")" > /dev/null 2>&1 || true
fi

raise_app() {
  /usr/bin/osascript -e 'tell application "WezTerm" to activate' 2> /dev/null || true
}

case "$pane" in
  %*)
    target=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}' 2> /dev/null || true)
    client=$(tmux list-clients -F '#{client_name}	#{client_termname}	#{client_activity}' 2> /dev/null |
      jq -Rrs 'split("\n") | map(split("\t") | select(length == 3 and (.[1] | startswith("wezterm")))) | sort_by(.[2] | tonumber) | last | .[0] // empty')
    if [ -n "$target" ] && [ -n "$client" ]; then
      tmux switch-client -c "$client" -t "$target" 2> /dev/null || true
      tmux select-pane -t "$pane" 2> /dev/null || true
    fi
    raise_app
    exit 0
    ;;
esac

[ -n "$wz" ] || {
  raise_app
  exit 0
}

if [ -n "$pane" ] && "$wz" cli --no-auto-start activate-pane --pane-id "$pane" 2> /dev/null; then
  raise_app
  exit 0
fi

if [ -n "$session" ]; then
  alt=$("$wz" cli --no-auto-start list --format json 2> /dev/null |
    jq -r --arg w "$session" \
      '[.[] | select(.workspace == $w)] | (map(select(.is_active)) + .) | .[0].pane_id // empty' \
      2> /dev/null |
    head -1)
  if [ -n "$alt" ] && "$wz" cli --no-auto-start activate-pane --pane-id "$alt" 2> /dev/null; then
    raise_app
    exit 0
  fi
fi

raise_app
exit 0
