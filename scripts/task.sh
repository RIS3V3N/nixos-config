# shellcheck shell=bash
# task — task-based workspaces on top of hyprsplit (see modules/tasks.nix).
#
# A task owns one "slot" (1..N). Slot S is workspace (base*N + S) on every
# monitor, where base is the monitor's hyprsplit index (laptop 0, then the
# other outputs by name). Switching a task switches all monitors at once.
set -uo pipefail

N=@N@
ROOT=@ROOT@
VAULT=@VAULT_PATH@
DENY_JSON=@DENY_JSON@
DEFAULT_TOOLS=@DEFAULT_TOOLS@
declare -A TOOL_CMD TOOL_MON
@TOOL_DEFS@

STATE="${XDG_RUNTIME_DIR:-/tmp}/task"
SLOTS="$STATE/slots" # lines: "<slot> <name>"
mkdir -p "$STATE"
touch "$SLOTS"

declare -A NAMES=() URG=()
MONS=()
ROLE_BASE=()
NROLES=0

die() {
  echo "task: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  task new <name> [-d <repo-dir>] [-w tool[:monitor],...]   create or resume a task
  task goto <slot>                                          show a slot on all monitors
  task switch                                               pick an open or closed task
  task list                                                 open tasks
  task close [slot|name]                                    close all windows of a task
  task wrap [name]                                          summarize a task into its summary.md
  task fix                                                  re-spread windows over current monitors
EOF
  exit 2
}

slugify() { printf '%s' "$1" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9._-'; }

load_names() {
  NAMES=()
  local k v
  while read -r k v; do
    [ -n "$k" ] && NAMES[$k]=$v
  done <"$SLOTS"
}

set_name() {
  local rest
  rest=$(awk -v s="$1" -v n="$2" '$1!=s && $2!=n' "$SLOTS")
  {
    if [ -n "$rest" ]; then printf '%s\n' "$rest"; fi
    printf '%s %s\n' "$1" "$2"
  } >"$SLOTS"
}

clear_name() {
  local rest
  rest=$(awk -v s="$1" '$1!=s' "$SLOTS")
  if [ -n "$rest" ]; then printf '%s\n' "$rest" >"$SLOTS"; else : >"$SLOTS"; fi
}

# Print "<slot> <address>" for every mapped window on a regular workspace.
slot_rows() {
  hyprctl clients -j | jq -r --argjson n "$N" \
    '.[] | select(.mapped and .workspace.id > 0) | "\(((.workspace.id - 1) % $n) + 1) \(.address)"'
}

occupied() { slot_rows | cut -d' ' -f1 | sort -un; }
is_occupied() { occupied | grep -qx "$1"; }

current_slot() {
  hyprctl monitors -j | jq -r --argjson n "$N" \
    '.[] | select(.focused) | ((.activeWorkspace.id - 1) % $n) + 1'
}

focused_monitor() { hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'; }

# "<name> <hyprsplit base> <role>" per output.
# base: laptop first (monitor_priority), others by name. role: externals by x, laptop last.
monitors() {
  hyprctl monitors -j | jq -r '
    [.[] | select((.mirrorOf // "none") == "none")] as $all
    | [$all[] | select(.name | startswith("eDP"))] as $lap
    | [$all[] | select(.name | startswith("eDP") | not)] as $ext
    | (($ext | sort_by(.x)) + $lap | map(.name)) as $roles
    | ($lap + ($ext | sort_by(.name))) | to_entries[]
    | .value.name as $n | "\($n) \(.key) \($roles | index($n))"'
}

load_mons() {
  MONS=()
  ROLE_BASE=()
  local name base role
  while read -r name base role; do
    [ -n "$name" ] || continue
    MONS+=("$name $base")
    ROLE_BASE[role]=$base
  done < <(monitors)
  NROLES=${#MONS[@]}
  [ "$NROLES" -gt 0 ] || die "no monitors"
}

goto() {
  local slot=$1 focus row name base batch=""
  load_mons
  focus=$(focused_monitor)
  for row in "${MONS[@]}"; do
    read -r name base <<<"$row"
    [ "$name" = "$focus" ] && continue
    batch+="dispatch workspace $((base * N + slot)); "
  done
  # Focused monitor last so focus ends up where it started.
  for row in "${MONS[@]}"; do
    read -r name base <<<"$row"
    [ "$name" = "$focus" ] && batch+="dispatch workspace $((base * N + slot)); "
  done
  hyprctl --batch "$batch" >/dev/null
}

addrs() { hyprctl clients -j | jq -r '.[].address' | sort; }

# Quoted claude flags: stable per-task session, notes vault readable, Files/ denied.
claude_args() {
  local tdir=$1 sid=$2 mode=--session-id prompt
  [ -z "$(find "$HOME/.claude/projects" -name "$sid.jsonl" -print -quit 2>/dev/null)" ] || mode=--resume
  prompt="Task notes (the user's scratch): $tdir/notes.md. Knowledge vault: $VAULT (layout in AGENTS.md). Task summary goes in $tdir/summary.md."
  printf '%q ' "$mode" "$sid" --add-dir "$VAULT" --settings "$DENY_JSON" --append-system-prompt "$prompt"
}

# Start a command on workspace $1 and pin the window it creates there (tagged with role $3).
launch() {
  local ws=$1 cmd=$2 role=$3 before addr="" i
  before=$(addrs)
  hyprctl dispatch exec "[workspace $ws silent] $cmd" >/dev/null
  for ((i = 0; i < 150; i++)); do
    addr=$(comm -13 <(printf '%s\n' "$before") <(addrs) | head -n1)
    [ -n "$addr" ] && break
    sleep 0.2
  done
  if [ -z "$addr" ]; then
    echo "task: no window appeared for: $cmd" >&2
    return
  fi
  hyprctl --batch "dispatch movetoworkspacesilent $ws,address:$addr; dispatch tagwindow +tm$role address:$addr" >/dev/null
}

open_task() {
  local name="" dir="" with="" slug tdir repo tools slot spec tool mon cmd base k sid
  while [ $# -gt 0 ]; do
    case $1 in
    -d | --dir) dir=${2:-}; shift 2 ;;
    -w | --with) with=${2:-}; shift 2 ;;
    -*) usage ;;
    *) name=$1; shift ;;
    esac
  done
  [ -n "$name" ] || usage
  slug=$(slugify "$name")
  [ -n "$slug" ] || die "invalid task name: $name"

  load_names
  slot=""
  for k in "${!NAMES[@]}"; do
    [ "${NAMES[$k]}" = "$slug" ] && slot=$k
  done
  if [ -n "$slot" ] && is_occupied "$slot"; then
    goto "$slot"
    return
  fi

  tdir="$ROOT/$slug"
  mkdir -p "$tdir"
  [ -f "$tdir/notes.md" ] || printf '# %s\n\n' "$name" >"$tdir/notes.md"
  [ -z "$dir" ] || realpath "$dir" >"$tdir/repo"
  [ -f "$tdir/repo" ] || pwd >"$tdir/repo"
  [ -z "$with" ] || printf '%s\n' "$with" >"$tdir/tools"
  [ -f "$tdir/tools" ] || printf '%s\n' "$DEFAULT_TOOLS" >"$tdir/tools"
  [ -f "$tdir/session" ] || uuidgen >"$tdir/session"
  [ -f "$tdir/created" ] || date -Iseconds >"$tdir/created"
  repo=$(<"$tdir/repo")
  tools=$(<"$tdir/tools")
  sid=$(<"$tdir/session")

  slot=""
  for ((k = 1; k <= N; k++)); do
    if ! is_occupied "$k"; then slot=$k; break; fi
  done
  [ -n "$slot" ] || die "all $N slots are in use"

  set_name "$slot" "$slug"
  goto "$slot"

  for spec in ${tools//,/ }; do
    tool=${spec%%:*}
    mon=${spec#*:}
    [ "$mon" = "$spec" ] && mon=${TOOL_MON[$tool]:-0}
    cmd=${TOOL_CMD[$tool]:-}
    if [ -z "$cmd" ]; then
      echo "task: unknown tool: $tool" >&2
      continue
    fi
    cmd=${cmd//@DIR@/$(printf '%q' "$repo")}
    cmd=${cmd//@NOTES@/$(printf '%q' "$tdir/notes.md")}
    cmd=${cmd//@VAULT@/$(printf '%q' "$VAULT")}
    if [[ $cmd == *@CLAUDE_ARGS@* ]]; then cmd=${cmd//@CLAUDE_ARGS@/$(claude_args "$tdir" "$sid")}; fi
    base=${ROLE_BASE[mon % NROLES]}
    launch "$((base * N + slot))" "$cmd" "$mon"
  done
}

cmd_list() {
  local c s
  load_names
  slot_rows | cut -d' ' -f1 | sort -n | uniq -c | while read -r c s; do
    printf '%s\t%s\t%s\n' "$s" "${NAMES[$s]:--}" "$c"
  done
}

cmd_switch() {
  local lines=() occ s d n choice first rest open=" "
  load_names
  occ=" $(occupied | tr '\n' ' ')"
  for ((s = 1; s <= N; s++)); do
    if [[ $occ == *" $s "* ]]; then
      lines+=("$s  ${NAMES[$s]:-}")
      open+="${NAMES[$s]:-} "
    fi
  done
  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    [[ $open == *" $n "* ]] || lines+=("-  $n")
  done
  [ ${#lines[@]} -gt 0 ] || return 0
  choice=$(printf '%s\n' "${lines[@]}" | fuzzel --dmenu --prompt 'task: ') || return 0
  read -r first rest <<<"$choice"
  if [ "$first" = "-" ]; then open_task "$rest"; else goto "$first"; fi
}

cmd_close() {
  local arg=${1:-} slot batch k
  load_names
  if [ -z "$arg" ]; then
    slot=$(current_slot)
  elif [[ $arg =~ ^[0-9]+$ ]]; then
    slot=$arg
  else
    arg=$(slugify "$arg")
    slot=""
    for k in "${!NAMES[@]}"; do
      [ "${NAMES[$k]}" = "$arg" ] && slot=$k
    done
  fi
  [ -n "$slot" ] || die "unknown task: $arg"
  batch=$(hyprctl clients -j | jq -r --argjson n "$N" --argjson s "$slot" \
    '[.[] | select(.mapped and .workspace.id > 0 and (((.workspace.id - 1) % $n) + 1) == $s) | "dispatch closewindow address:\(.address)"] | join("; ")')
  if [ -n "$batch" ]; then hyprctl --batch "$batch" >/dev/null; fi
  clear_name "$slot"
}

# Summarize a task with a forked copy of its Claude session; never touches the vault itself.
cmd_wrap() {
  local arg=${1:-} slug tdir repo sid created prompt
  if [ -n "$arg" ]; then
    slug=$(slugify "$arg")
  else
    load_names
    slug=${NAMES[$(current_slot)]:-}
  fi
  [ -n "$slug" ] || die "no task given and current slot has no name"
  tdir="$ROOT/$slug"
  [ -f "$tdir/session" ] || die "no recorded session for: $slug"
  repo=$(<"$tdir/repo")
  sid=$(<"$tdir/session")
  created=$(<"$tdir/created")
  prompt="This task is done. Write one markdown document with exactly two sections.
## Summary: what was done and why, key decisions, gotchas and how they were resolved, useful commands, links to PRs and issues. Use the task notes at $tdir/notes.md and run git log --since=$created --stat in the repo.
## Suggested vault updates: for each piece of durable knowledge, a heading ### <existing note path relative to $VAULT/braindump> followed by the exact text to append; check the note exists first. Leave the section empty if nothing is durable.
Output only the markdown document."
  echo "task: summarizing $slug ..." >&2
  (
    cd "$repo" &&
      printf '%s' "$prompt" | claude --resume "$sid" --fork-session -p \
        --add-dir "$VAULT" --settings "$DENY_JSON" \
        --allowedTools "Read,Glob,Grep,Bash(git log:*),Bash(git diff:*),Bash(git show:*),Bash(git status:*)"
  ) >"$tdir/summary.md.tmp" && mv "$tdir/summary.md.tmp" "$tdir/summary.md" && echo "task: wrote $tdir/summary.md" >&2
}

# Put tagged windows back on the monitor their role maps to (after dock/undock).
cmd_fix() {
  local addr ws role slot target batch=""
  load_mons
  while read -r addr ws role; do
    [ -n "$addr" ] || continue
    slot=$(((ws - 1) % N + 1))
    target=$((ROLE_BASE[role % NROLES] * N + slot))
    [ "$target" -ne "$ws" ] && batch+="dispatch movetoworkspacesilent $target,address:$addr; "
  done < <(hyprctl clients -j | jq -r '
    .[] | select(.mapped and .workspace.id > 0)
    | (([.tags[]? | select(test("^tm[0-9]+$")) | .[2:]] | first) // empty) as $r
    | "\(.address) \(.workspace.id) \($r)"')
  if [ -n "$batch" ]; then hyprctl --batch "$batch" >/dev/null; fi
}

events() {
  socat -u "UNIX-CONNECT:${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" -
}

cmd_watch() {
  local line
  events | while read -r line; do
    case $line in
    monitoradded* | monitorremoved*)
      sleep 3
      cmd_fix
      ;;
    esac
  done
}

render() {
  local cur rows slot addr s label text="" occ=" " urg=" "
  cur=$(current_slot)
  load_names
  rows=$(slot_rows)
  while read -r slot addr; do
    [ -n "$slot" ] || continue
    occ+="$slot "
    if [ "$slot" = "$cur" ]; then unset 'URG[$addr]'; fi
    if [ -n "${URG[$addr]:-}" ]; then urg+="$slot "; fi
  done <<<"$rows"
  for ((s = 1; s <= N; s++)); do
    label=$s
    [[ $occ == *" $s "* ]] && [ -n "${NAMES[$s]:-}" ] && label="$s ${NAMES[$s]}"
    if [[ $urg == *" $s "* ]]; then
      text+="<span foreground=\"#f38ba8\"> $label ! </span>"
    elif [ "$s" = "$cur" ]; then
      text+="<span background=\"#89b4fa\" foreground=\"#1e1e2e\"> ${label} </span>"
    elif [[ $occ == *" $s "* ]]; then
      text+="<span foreground=\"#a6adc8\"> $label </span>"
    fi
  done
  jq -cn --arg t "$text" '{text: $t}'
}

cmd_waybar() {
  local line
  render
  events | while read -r line; do
    case $line in
    'urgent>>'*)
      URG["0x${line#urgent>>}"]=1
      render
      ;;
    workspace* | focusedmon* | openwindow* | closewindow* | movewindow* | monitor* | createworkspace* | destroyworkspace*)
      render
      ;;
    esac
  done
}

case "${1:-}" in
new | open | resume) shift; open_task "$@" ;;
goto) [ -n "${2:-}" ] || usage; goto "$2" ;;
switch) cmd_switch ;;
list) cmd_list ;;
close) cmd_close "${2:-}" ;;
wrap) cmd_wrap "${2:-}" ;;
fix) cmd_fix ;;
watch) cmd_watch ;;
waybar) cmd_waybar ;;
*) usage ;;
esac
