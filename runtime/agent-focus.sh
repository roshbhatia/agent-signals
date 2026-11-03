pane=${1:-}
session=${2:-}

notifier=$(command -v alerter 2> /dev/null || true)
if [ -n "$notifier" ] && [ -n "$pane" ]; then
  "$notifier" --remove "$(agent_group "" "" "$pane")" > /dev/null 2>&1 || true
fi
if [ -n "$pane" ]; then
  case "$pane" in
    %*) exec ty terminal focus "$pane" ;;
    *) exec ty terminal focus "wezterm:$pane" ;;
  esac
fi
if [ -n "$session" ]; then
  exec ty terminal open "$session"
fi
