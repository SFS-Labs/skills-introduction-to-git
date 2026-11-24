#!/bin/bash
# Run the course script, then upload its log to the repository so the run is
# inspectable without a terminal in the Codespace. Progress is also published
# to a public ntfy topic so failures before the upload are visible.

set -u

LOG=/workspaces/course-run.log
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
REPO="${GITHUB_REPOSITORY:-SFS-Labs/skills-introduction-to-git}"

notify() {
  local msg="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -m 10 -d "$msg" https://ntfy.sh/sfs-intro-git-20261124 >/dev/null 2>&1 || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,urllib.request; urllib.request.urlopen(urllib.request.Request("https://ntfy.sh/sfs-intro-git-20261124", data=sys.argv[1].encode(), method="POST"), timeout=10).read()' "$msg" >/dev/null 2>&1 || true
  fi
}

: > "$LOG"
{
  echo "=== diagnostic ${RUN_ID} ==="
  echo "repo=${REPO} codespace=${CODESPACE_NAME:-unset} token=${GITHUB_TOKEN:+set}"
  echo "tools curl=$(command -v curl || echo missing) jq=$(command -v jq || echo missing) tmux=$(command -v tmux || echo missing) inotifywait=$(command -v inotifywait || echo missing) python3=$(command -v python3 || echo missing)"
  echo "hooksPath=$(git config --global --get core.hooksPath 2>/dev/null || echo unset)"
} >> "$LOG"
notify "diag ${RUN_ID} start $(tail -n 2 "$LOG" | tr '\n' ' | ')"

upload_log() {
  local name="$1"
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "upload ${name}: no token" >> "$LOG"
    return 0
  fi
  local encoded code
  encoded=$(base64 "$LOG" | tr -d '\n')
  code=$(curl -sS -m 30 -o /workspaces/diag/upload-response.json -w '%{http_code}' -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/contents/diagnostics/${name}.log" \
    -d "{\"message\":\"chore: upload codespace diagnostics ${name}\",\"content\":\"${encoded}\",\"branch\":\"course-run\"}" || echo 000)
  echo "upload ${name}: HTTP ${code}" >> "$LOG"
  notify "upload ${name}: HTTP ${code}"
}

watch_log() {
  while true; do
    sleep 20
    notify "progress $(date -u +%H:%M:%S): $(tail -n 3 "$LOG" 2>/dev/null | tr '\n' ' | ' | cut -c1-3500)"
  done
}
watch_log &
WATCH_PID=$!

upload_log "${RUN_ID}-start"
bash "/workspaces/${RepositoryName:-skills-introduction-to-git}/.devcontainer/course-run.sh" >> "$LOG" 2>&1
STATUS=$?
echo "course-run exit status: ${STATUS}" >> "$LOG"
kill "$WATCH_PID" 2>/dev/null || true
upload_log "${RUN_ID}-final"
notify "diag ${RUN_ID} done status=${STATUS}: $(tail -n 8 "$LOG" | tr '\n' ' | ' | cut -c1-3500)"
