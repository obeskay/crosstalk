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

TMP_OUT=""
TMP_ERR=""
# EXIT, not RETURN: a RETURN trap does not run when die() calls exit, nor when
# set -e aborts the script, which is exactly when cleanup matters most.
cleanup() { [ -n "$TMP_OUT" ] && rm -f "$TMP_OUT"; [ -n "$TMP_ERR" ] && rm -f "$TMP_ERR"; return 0; }
trap cleanup EXIT

die() { printf 'crosstalk: %s\n' "$1" >&2; exit "${2:-1}"; }

# Thread names reach the filesystem, so keep them to a safe alphabet. The
# hyphen MUST stay last in this set: written as '.-_' it becomes an ASCII range
# spanning '/', which would let '../..' through into the path.
safe_name() { printf '%s' "$1" | tr -c '[:alnum:]._-' '_'; }

# One JSON field out of agy's single-line object. python3 then node; both ship
# with the platforms agy runs on. No jq dependency, no hand-rolled parser.
# Supports dotted keys (e.g. usage.total_tokens). Returns non-zero when the
# payload is not the JSON we expect, so callers can report that instead of dying
# silently under set -e.
json_field() {
  local field=$1 file=$2
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json,sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    v = v.get(k) if isinstance(v, dict) else None
sys.stdout.write("" if v is None else str(v))
' "$file" "$field" 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e '
const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const v = process.argv[2].split(".").reduce((a, k) => (a && typeof a === "object" ? a[k] : undefined), o);
process.stdout.write(v === undefined || v === null ? "" : String(v));
' "$file" "$field" 2>/dev/null
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
      --thread)  thread=$(safe_name "${2:?--thread needs a name}"); shift 2 ;;
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
    thread_file="$THREADS_DIR/$thread"
    if [ -s "$thread_file" ]; then
      args+=(--conversation "$(cat "$thread_file")")
    fi
  fi

  TMP_OUT=$(mktemp); TMP_ERR=$(mktemp)
  if ! agy "${args[@]}" >"$TMP_OUT" 2>"$TMP_ERR"; then
    printf 'crosstalk: agy failed\n' >&2
    sed 's/^/  /' "$TMP_ERR" >&2 || true
    return 1
  fi

  local status
  if ! status=$(json_field status "$TMP_OUT"); then
    printf 'crosstalk: could not parse agy output as JSON. Raw output:\n' >&2
    head -c 2000 "$TMP_OUT" | sed 's/^/  /' >&2
    return 1
  fi

  if [ "$status" != "SUCCESS" ]; then
    # The failure reason lives in `response`; surfacing only the status leaves
    # the user with nothing to act on.
    local detail; detail=$(json_field response "$TMP_OUT" 2>/dev/null || true)
    printf 'crosstalk: agy returned status=%s\n' "${status:-<empty>}" >&2
    [ -n "$detail" ] && printf '%s\n' "$detail" | sed 's/^/  /' >&2
    return 1
  fi

  local conv; conv=$(json_field conversation_id "$TMP_OUT" 2>/dev/null || true)
  if [ -n "$thread_file" ] && [ -n "$conv" ]; then
    printf '%s' "$conv" >"$thread_file" 2>/dev/null \
      || printf 'crosstalk: could not persist thread "%s"\n' "$thread" >&2
  fi

  json_field response "$TMP_OUT"

  # Ledger: what this call cost, so the skill can report what was offloaded.
  # `thread` is already sanitised to [alnum._-], so it cannot break the JSON.
  local total dur turns
  total=$(json_field usage.total_tokens "$TMP_OUT" 2>/dev/null || true)
  dur=$(json_field duration_seconds "$TMP_OUT" 2>/dev/null || true)
  turns=$(json_field num_turns "$TMP_OUT" 2>/dev/null || true)
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
calls=[]
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try: calls.append(json.loads(line))
    except ValueError: continue          # a corrupt line must not kill the report
if not calls:
    print("no readable calls in the ledger"); raise SystemExit
tok=sum(c.get("tokens") or 0 for c in calls); sec=sum(c.get("seconds") or 0 for c in calls)
print(f"{len(calls)} calls, {tok:,} tokens offloaded to Gemini, {sec:.0f}s of work")
by={}
for c in calls:
    t=c.get("thread","adhoc"); by[t]=by.get(t,0)+(c.get("tokens") or 0)
for t,n in sorted(by.items(),key=lambda x:-x[1])[:10]: print(f"  {n:>10,}  {t}")
PY
  else
    wc -l <"$LEDGER" | xargs printf '%s calls recorded (install python3 for the breakdown)\n'
  fi
}

cmd_threads() {
  [ -d "$THREADS_DIR" ] || { echo "no threads yet"; return 0; }
  local found=0 f
  # (*) misses dotfiles, and '.' is a legal thread character.
  for f in "$THREADS_DIR"/* "$THREADS_DIR"/.[!.]*; do
    [ -f "$f" ] || continue
    found=1
    printf '%-28s %s\n' "$(basename "$f")" "$(cat "$f")"
  done
  [ "$found" -eq 1 ] || echo "no threads yet"
}

cmd_reset() {
  if [ -n "${1:-}" ]; then
    local name; name=$(safe_name "$1")
    rm -f "$THREADS_DIR/$name"
    echo "thread '$name' reset"
  else
    rm -rf "$THREADS_DIR"
    echo "all threads reset"
  fi
}

cmd_help() {
  cat <<'EOF'
crosstalk — ask Antigravity (Gemini) a question from anywhere, keep the thread.

Usage:
  crosstalk.sh ask "<prompt>" [--thread NAME] [--model M] [--effort low|medium|high] [--timeout DUR]
  crosstalk.sh stats
  crosstalk.sh threads
  crosstalk.sh reset [NAME]
EOF
}

case "${1:-}" in
  ask)            shift; cmd_ask "$@" ;;
  stats)          cmd_stats ;;
  threads)        cmd_threads ;;
  reset)          shift; cmd_reset "${1:-}" ;;
  help|--help|-h) cmd_help ;;
  *) die "usage: crosstalk.sh {ask|stats|threads|reset|--help}" 2 ;;
esac
