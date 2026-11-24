#!/bin/bash

# Start exercise monitor
/home/vscode/.vscode-remote/data/Machine/exercise-monitor/start.sh

# Run the automated course steps in this real Codespace. The course monitor
# and Git hooks remain the only source of repository_dispatch events.
COURSE_RUN="/workspaces/${RepositoryName}/.devcontainer/course-run.sh"
if [ -f "$COURSE_RUN" ]; then
  nohup bash "$COURSE_RUN" >> /workspaces/course-run.log 2>&1 < /dev/null &
fi
