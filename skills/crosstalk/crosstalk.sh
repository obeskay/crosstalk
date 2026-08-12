#!/usr/bin/env bash
# crosstalk — ask Antigravity (Gemini) a question from anywhere, keep the thread.
#
# Usage:
#   crosstalk.sh ask "<prompt>" [--thread NAME] [--model M] [--effort low|medium|high] [--timeout DUR]
#   crosstalk.sh stats
#   crosstalk.sh threads
#   crosstalk.sh reset [NAME]
#
# Exits non-zero on failure. Prints the answer on stdout; everything else on stderr.

set -euo pipefail

STATE_DIR="${CROSSTALK_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/crosstalk}"
THREADS_DIR="$STATE_DIR/threads"
LEDGER="$STATE_DIR/ledger.jsonl"

die() { printf 'crosstalk: %s\n' "$1" >&2; exit "${2:-1}"; }

# One JSON field out of agy's single-line object. python3 then node; both ship
# with the platforms agy runs on. No jq dependency, no hand-rolled parser.
json_field() {
  local field=$1 file=$2
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],"") or "")' "$file" "$field"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const o=require("fs").readFileSync(process.argv[1],"utf8");process.stdout.write(String(JSON.parse(o)[process.argv[2]]??""))' "$file" "$field"
  else
    die "need python3 or node to read agy's JSON output"
  fi
}

cmd_ask() {
  local prompt=${1:-} thread="" model="" effort="" timeout="10m"
  [ -n "$prompt" ] || die "ask needs a prompt"
  shift || true
  while [ $# -gt 0 ]; do
    case $1 in
      --thread)  thread=${2:?--thread needs a name}; shift 2 ;;
      --model)   model=${2:?--model needs a value}; shift 2 ;;
      --effort)  effort=${2:?--effort needs a value}; shift 2 ;;
      --timeout) timeout=${2:?--timeout needs a value}; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  command -v agy >/dev/null 2>&1 || die "agy not found on PATH — install the Antigravity CLI first"

  local args=(-p "$prompt" --output-format json --print-timeout "$timeout")
  [ -n "$model" ]  && args+=(--model "$model")
  [ -n "$effort" ] && args+=(--effort "$effort")

  # Resume the thread when we have already talked about this topic.
  local thread_file=""
  if [ -n "$thread" ]; then
    mkdir -p "$THREADS_DIR"
    thread_file="$THREADS_DIR/$(printf '%s' "$thread" | tr -c '[:alnum:]._-' '_')"
    if [ -s "$thread_file" ]; then
      args+=(--conversation "$(cat "$thread_file")")
    fi
  fi

  local out; out=$(mktemp)
  trap 'rm -f "$out"' RETURN
  if ! agy "${args[@]}" >"$out" 2>"$out.err"; then
    printf 'crosstalk: agy failed\n' >&2
    sed 's/^/  /' "$out.err" >&2 || true
    rm -f "$out.err"
    return 1
  fi
  rm -f "$out.err"

  local status; status=$(json_field status "$out")
  if [ "$status" != "SUCCESS" ]; then
    die "agy returned status=$status"
  fi

  local conv; conv=$(json_field conversation_id "$out")
  [ -n "$thread_file" ] && [ -n "$conv" ] && printf '%s' "$conv" >"$thread_file"

  json_field response "$out"

  # Ledger: what this call cost, so the skill can report what was offloaded.
  local total dur turns
  total=$(json_field total_tokens "$out"); dur=$(json_field duration_seconds "$out"); turns=$(json_field num_turns "$out")
  if [ -z "$total" ]; then
    total=$(
      if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("usage",{}).get("total_tokens",0))' "$out"
      else
        node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(o.usage?.total_tokens??0))' "$out"
      fi
    )
  fi
  mkdir -p "$STATE_DIR"
  printf '{"thread":"%s","tokens":%s,"seconds":%s,"turns":%s}\n' \
    "${thread:-adhoc}" "${total:-0}" "${dur:-0}" "${turns:-0}" >>"$LEDGER"

  printf '\n[crosstalk] %s tokens on Gemini, %ss%s\n' \
    "${total:-0}" "${dur:-0}" "${thread:+, thread: $thread}" >&2
}

cmd_stats() {
  [ -s "$LEDGER" ] || { echo "no crosstalk calls recorded yet"; return 0; }
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$LEDGER" <<'PY'
import json,sys
calls=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
tok=sum(c.get("tokens",0) for c in calls); sec=sum(c.get("seconds",0) for c in calls)
print(f"{len(calls)} calls, {tok:,} tokens offloaded to Gemini, {sec:.0f}s of work")
by={}
for c in calls: by[c.get("thread","adhoc")]=by.get(c.get("thread","adhoc"),0)+c.get("tokens",0)
for t,n in sorted(by.items(),key=lambda x:-x[1])[:10]: print(f"  {n:>10,}  {t}")
PY
  else
    wc -l <"$LEDGER" | xargs printf '%s calls recorded (install python3 for the breakdown)\n'
  fi
}

cmd_threads() {
  [ -d "$THREADS_DIR" ] || { echo "no threads yet"; return 0; }
  for f in "$THREADS_DIR"/*; do
    [ -e "$f" ] || continue
    printf '%-28s %s\n' "$(basename "$f")" "$(cat "$f")"
  done
}

cmd_reset() {
  if [ -n "${1:-}" ]; then
    rm -f "$THREADS_DIR/$(printf '%s' "$1" | tr -c '[:alnum:]._-' '_')"
    echo "thread '$1' reset"
  else
    rm -rf "$THREADS_DIR"
    echo "all threads reset"
  fi
}

case "${1:-}" in
  ask)     shift; cmd_ask "$@" ;;
  stats)   cmd_stats ;;
  threads) cmd_threads ;;
  reset)   shift; cmd_reset "${1:-}" ;;
  *) die "usage: crosstalk.sh {ask|stats|threads|reset}" 2 ;;
esac
