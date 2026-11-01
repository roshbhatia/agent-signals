agent=${1:-agent}
reason=${2:-attention}
focus_exe=${3:-}
# wezterm calls this from its own process: no hook JSON, no WEZTERM_PANE, cwd is /.
arg_pane=${4:-}
arg_cwd=${5:-}

an_agents="${XDG_STATE_HOME:-$HOME/.local/state}/agents"

notifier=$(command -v alerter 2> /dev/null) || exit 0

input=""
if [ ! -t 0 ]; then
  input=$(cat 2> /dev/null)
fi

json() {
  [ -n "$input" ] || return 0
  printf '%s' "$input" | jq -r "$1 // empty" 2> /dev/null
}

cwd=$(json '.cwd')
[ -n "$cwd" ] || cwd=$arg_cwd
[ -n "$cwd" ] || cwd=$PWD
msg=$(json '.message')
notif_type=$(json '.notification_type')

pane=${WEZTERM_PANE:-$arg_pane}
agent_identity "$cwd" "$pane"
session=$AI_SESSION
repo=$AI_REPO

if [ -n "$session" ] && [ -n "$repo" ] && [ "$session" != "$repo" ]; then
  context="$session · $repo"
elif [ -n "$session" ]; then
  context="$session"
elif [ -n "$repo" ]; then
  context="$repo"
else
  context=$(basename "$cwd")
fi

icons="${XDG_DATA_HOME:-$HOME/.local/share}/agent-notify/icons"
label=$(jq -r --arg agent "$agent" '.agents[$agent].label // empty' "$notify_config")
[ -n "$label" ] || label=$(agent_label "$agent")
icon=$(jq -r --arg agent "$agent" '.agents[$agent].icon // .defaultIcon // empty' "$notify_config")
[ -n "$icon" ] || icon="$icons/$agent.png"
if [ ! -f "$icon" ]; then
  icon=$(jq -r '.defaultIcon // empty' "$notify_config")
fi
[ -f "$icon" ] || icon="$icons/agent.png"

# Any non-zero is unclassified, and this path suppresses rather than spams.
classified=$(agent_classify "$reason" "$notif_type" "$msg") || exit 0
reason=$classified

profile=${AGENT_NOTIFY_PROFILE:-default}
policy=$(jq -ce --arg reason "$reason" --arg profile "$profile" '
  .defaults * (.events[$reason] // {}) * (.profiles[$profile].defaults // {}) * (.profiles[$profile].events[$reason] // {})
' "$notify_config") || exit 2
[ "$(printf '%s' "$policy" | jq -r '.enabled')" = true ] || exit 0
what=$(printf '%s' "$policy" | jq -r '.message')
sound=$(printf '%s' "$policy" | jq -r '.sound // empty')
notif_timeout=$(printf '%s' "$policy" | jq -r '.timeoutSeconds')
cooldown=$(printf '%s' "$policy" | jq -r '.cooldownSeconds')
minimum=$(printf '%s' "$policy" | jq -r '.minDurationSeconds')
content_image=$(printf '%s' "$policy" | jq -r '.contentImage')

case "$reason" in
  approval) notif_timeout=${AGENT_NOTIFY_TIMEOUT_APPROVAL:-$notif_timeout} ;;
  idle) notif_timeout=${AGENT_NOTIFY_TIMEOUT_IDLE:-$notif_timeout} ;;
  done) notif_timeout=${AGENT_NOTIFY_TIMEOUT_DONE:-$notif_timeout} ;;
  *) notif_timeout=${AGENT_NOTIFY_TIMEOUT_DEFAULT:-$notif_timeout} ;;
esac
[[ $notif_timeout =~ ^[0-9]+$ ]] || {
  printf 'agent-notify: timeout must be an integer\n' >&2
  exit 2
}

if [ "$minimum" -gt 0 ] && [[ $pane =~ ^[0-9]+$ ]]; then
  an_panes=$(sysinit_path agentPanes) || an_panes="$an_agents/panes"
  start_file="$an_panes/$pane.start"
  if [ -f "$start_file" ]; then
    start=$(cat "$start_file" 2> /dev/null) || start=0
    [[ $start =~ ^[0-9]+$ ]] || start=0
    now=$(date +%s)
    elapsed=$((now - start))
    [ "$elapsed" -lt "$minimum" ] && exit 0
  fi
fi

if [ "$cooldown" -gt 0 ]; then
  notif_dir=$(sysinit_path agentNotif) || notif_dir="$an_agents/notif"
  mkdir -p "$notif_dir" 2> /dev/null || true
  dedup_key=$(printf '%s' "$agent|$context|$pane|$reason" | cksum | cut -d' ' -f1)
  dedup_file="$notif_dir/$dedup_key"
  now=$(date +%s)
  if [ -f "$dedup_file" ]; then
    last=$(cat "$dedup_file" 2> /dev/null) || last=0
    [[ $last =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$cooldown" ] && exit 0
  fi
  printf '%s' "$now" > "$dedup_file" 2> /dev/null || true
fi

title="$label · $what"
suffix=""
[ -n "$pane" ] && suffix=$(agent_review_suffix "$pane")
if [ -n "$msg" ]; then
  body="$msg$suffix"
else
  body=${suffix# — } # the title already says what happened; do not repeat it
fi
[ -n "$body" ] || body=$what
group=$(agent_group "$agent" "$context" "$pane")

args=(
  --title "$title"
  --subtitle "$context"
  --message "$body"
  --group "$group"
  --timeout "$notif_timeout"
)

[ -z "$sound" ] || args+=(--sound "$sound")
if [ -f "$icon" ]; then
  args+=(--app-icon "$icon")
  [ "$content_image" != true ] || args+=(--content-image "$icon")
fi

(
  outcome=$("$notifier" "${args[@]}" 2> /dev/null) || outcome=""
  if [ -n "$focus_exe" ]; then
    case "$outcome" in
      @CONTENTCLICKED | @ACTIONCLICKED)
        "$focus_exe" "$pane" "$session" > /dev/null 2>&1 || true
        ;;
    esac
  fi
) < /dev/null > /dev/null 2>&1 &
disown 2> /dev/null || true

exit 0
