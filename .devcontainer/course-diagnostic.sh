#!/bin/bash
# Run the course script, then upload its log to the repository so the run is
# inspectable without a terminal in the Codespace.

set -u

LOG=/workspaces/course-run.log
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
REPO="${GITHUB_REPOSITORY:-SFS-Labs/skills-introduction-to-git}"

: > "$LOG"
{
  echo "=== diagnostic ${RUN_ID} ==="
  echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-unset}"
  echo "CODESPACE_NAME=${CODESPACE_NAME:-unset}"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN:+set}"
  echo "RepositoryName=${RepositoryName:-unset}"
} >> "$LOG"

upload_log() {
  local name="$1"
  [ -n "${GITHUB_TOKEN:-}" ] || return 0
  local encoded
  encoded=$(base64 "$LOG" | tr -d '\n')
  curl -fsS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/contents/diagnostics/${name}.log" \
    -d "{\"message\":\"chore: upload codespace diagnostics ${name}\",\"content\":\"${encoded}\",\"branch\":\"course-run\"}" \
    >/dev/null 2>&1 || echo "upload ${name} failed" >> "$LOG"
}

upload_log "${RUN_ID}-start"
bash "/workspaces/${RepositoryName}/.devcontainer/course-run.sh" >> "$LOG" 2>&1
STATUS=$?
echo "course-run exit status: ${STATUS}" >> "$LOG"
upload_log "${RUN_ID}-final"
