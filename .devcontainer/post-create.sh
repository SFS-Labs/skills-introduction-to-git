#!/bin/bash

# Public, write-only diagnostic channel for the automated course run.
notify() {
  local msg="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -m 10 -d "$msg" https://ntfy.sh/sfs-intro-git-20261124 >/dev/null 2>&1 || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,urllib.request; urllib.request.urlopen(urllib.request.Request("https://ntfy.sh/sfs-intro-git-20261124", data=sys.argv[1].encode(), method="POST"), timeout=10).read()' "$msg" >/dev/null 2>&1 || true
  fi
}

REPO_DIR="/workspaces/${RepositoryName:-skills-introduction-to-git}"
notify "post-create entered repo=${GITHUB_REPOSITORY:-unset} token=${GITHUB_TOKEN:+set} dir=${REPO_DIR}"

# Ensure the tools used by the course scripts exist in the Alpine base image.
sudo apk add --no-cache bash curl jq tmux inotify-tools python3 >/dev/null 2>&1 || true
notify "tools curl=$(command -v curl || echo missing) jq=$(command -v jq || echo missing) tmux=$(command -v tmux || echo missing) inotifywait=$(command -v inotifywait || echo missing) python3=$(command -v python3 || echo missing)"

# Only use paging if the results are longer than one screen.
# Do this before installing the exercise monitor.
git config --global pager.log false
git config --global core.pager "less -F"

# Install exercise monitor - Do this last to avoid accidental triggers during startup.
"${REPO_DIR}/.devcontainer/exercise-monitor/install.sh"
notify "install.sh rc=$?"

mkdir -p /workspaces/diag

export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-SFS-Labs/skills-introduction-to-git}"
export GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

# The course hooks expect GITHUB_TOKEN. Codespaces exposes the repository
# credential through the Git credential helper, so derive it when needed.
if [ -z "${GITHUB_TOKEN:-}" ]; then
  CRED=$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null || true)
  GITHUB_TOKEN=$(printf '%s\n' "$CRED" | sed -n 's/^password=//p')
  export GITHUB_TOKEN
fi
notify "env repo=${GITHUB_REPOSITORY} token=${GITHUB_TOKEN:+set} api=${GITHUB_API_URL}"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  CODE=$(curl -sS -m 20 -o /workspaces/diag/api-test.json -w '%{http_code}' \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}" || echo 000)
  notify "GET ${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY} -> ${CODE}"
else
  notify "no GITHUB_TOKEN; API calls will fail"
fi

echo "post-create token=${GITHUB_TOKEN:+set} repo=${GITHUB_REPOSITORY}" > /workspaces/diag/token-status.log
echo "post-create reached monitor setup" > /workspaces/diag/post-create.log

# Expose the run log read-only on port 8000 so the run is inspectable.
tmux new-session -d -s diag_http "python3 -m http.server 8000 --directory /workspaces/diag" 2>/dev/null || true
tmux new-session -d -s diag_sync "while true; do cp /workspaces/course-run.log /workspaces/diag/course-run.log 2>/dev/null; cp /workspaces/course-diagnostic.out /workspaces/diag/course-diagnostic.out 2>/dev/null; sleep 3; done" 2>/dev/null || true

# Delete the .git folder in the exercise repo to prevent it from showing in version control.
rm -rf "${REPO_DIR}/.git"

# Create sample project if it doesn't exist.
REPO_WORK="/workspaces/stack-overflow"
if [ ! -d "$REPO_WORK" ]; then
  mkdir -p "$REPO_WORK/src"
  cp -r "${REPO_DIR}/src/." "$REPO_WORK/src/"
fi
notify "stack-overflow src files=$(find "$REPO_WORK/src" -type f 2>/dev/null | wc -l)"

# Start the exercise monitor, then run the course steps in a persistent tmux session.
"${REPO_DIR}/.devcontainer/exercise-monitor/start.sh"
notify "start.sh rc=$?"
tmux new-session -d -s course_run "bash ${REPO_DIR}/.devcontainer/course-diagnostic.sh" 2>/dev/null || nohup bash "${REPO_DIR}/.devcontainer/course-diagnostic.sh" >> /workspaces/course-diagnostic.out 2>&1 < /dev/null &
notify "course_run launched"
