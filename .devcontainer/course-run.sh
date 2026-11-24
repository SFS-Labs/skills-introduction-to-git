#!/bin/bash
# Run the Introduction to Git exercise steps inside a real Codespace.
# The course's own monitor and Git hooks produce the repository_dispatch events.

set -u

LOG=/workspaces/course-run.log
exec >>"$LOG" 2>&1

echo "=== course-run $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

MARKER=/workspaces/.course-run-done
if [ -f "$MARKER" ]; then
  echo "marker exists; nothing to do"
  exit 0
fi

export GIT_AUTHOR_NAME="SFS Labs"
export GIT_AUTHOR_EMAIL="sfs-labs@users.noreply.github.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

api() {
  curl -fsS -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" "$@"
}

wait_active() {
  local id="$1"
  local name="$2"
  local state=""
  echo "waiting for workflow ${name} (${id})..."
  for _ in $(seq 1 150); do
    state=$(api "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${id}" \
      | tr -d '\n' \
      | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ "$state" = "active" ]; then
      echo "workflow ${name} (${id}) active"
      return 0
    fi
    sleep 2
  done
  echo "timeout waiting for workflow ${name} (${id}), last state=${state}"
  return 1
}

echo "repo=${GITHUB_REPOSITORY} codespace=${CODESPACE_NAME:-unset}"

# Let the tmux/inotify monitor from post-create.sh come up.
sleep 12

# Step 1: change the global Git config. The course monitor observes it and
# dispatches git-config-changed with config_type=global.
echo "step 1: writing global Git config"
git config --global user.name "SFS Labs"
git config --global user.email "sfs-labs@users.noreply.github.com"
git config --global --list
wait_active 429302938 "Step 2" || exit 1

# Step 2: initialize the sample project and make the three required commits.
echo "step 2: initializing project and creating three commits"
cd /workspaces/stack-overflown || exit 1
git init -b main
git config user.name "SFS Labs"
git config user.email "sfs-labs@users.noreply.github.com"
git add src/*
git commit -m "Initial commit"

cat > README.md <<'EOF'
# Stack Overflown

Organize the falling blocks into the current debug pattern before the stack overflows! 🌟
EOF
git add README.md
git commit -m "Start game documentation"

cat >> README.md <<'EOF'

## How to Develop

- `index.html` - the game container for playing
- `index.js` - the primary game logic
- `patterns.js` - the error patterns to match during gameplay
- `style.css` - the game formatting and styling
EOF
git add README.md
git commit -m "Start developer docs"
wait_active 429302949 "Step 3" || exit 1

# Step 3: inspect history, visit the first commit, then return to main.
echo "step 3: exploring history"
INITIAL_COMMIT=$(git rev-list --max-parents=0 HEAD)
git log --oneline
git checkout "$INITIAL_COMMIT"
git checkout main
wait_active 429302959 "Step 4" || exit 1

# Step 4: two real source changes with the required commit messages.
echo "step 4: changing source files"
python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/index.html")
text = path.read_text()
pattern = re.compile(
    r'(<div class="info-section">\s*)'
    r'<h3>Score</h3>\s*'
    r'<div class="score" id="score">0</div>\s*'
    r'<div class="status" id="status">Playing\.\.\.</div>\s*'
    r'(</div>)',
    re.S,
)
replacement = (
    r'\1'
    '<h3>Current Score</h3>\n'
    '          <div class="score" id="score">0</div>\n'
    '          <h3>High Score</h3>\n'
    '          <div class="high-score" id="high-score">0</div>\n'
    '        '
    r'\2'
)
new_text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("index.html info-section not found")
path.write_text(new_text)
PY
git add src/index.html
git commit -m "Add element for showing high score"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/patterns.js")
text = path.read_text()
pattern = re.compile(
    r'\{\s*name: "Null Pointer",\s*pattern: \[.*?\],\s*\}',
    re.S,
)
replacement = '''{
    name: "Null Pointer",
    pattern: [
      [0, 1, 1, 1, 0],
      [0, 1, 0, 1, 0],
      [0, 1, 1, 1, 0],
      [0, 0, 1, 0, 0],
      [0, 0, 1, 0, 0],
    ],
  }'''
new_text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("Null Pointer pattern not found")
path.write_text(new_text)
PY
git add src/patterns.js
git commit -m "Make null pointer pattern easier to complete"
wait_active 429302969 "Step 5" || exit 1

# Step 5: first branch with three commits and a real merge commit.
echo "step 5: branching and merging"
git branch fix-incomplete-high-score
git checkout fix-incomplete-high-score

python3 - <<'PY'
from pathlib import Path

path = Path("src/index.js")
text = path.read_text()
needle = "let score = 0;\n"
if needle not in text:
    raise SystemExit("score declaration not found")
path.write_text(text.replace(needle, needle + "let highScore = 0;\n", 1))
PY
git add src/index.js
git commit -m "Add new variable for tracking high score"

python3 - <<'PY'
from pathlib import Path

path = Path("src/index.js")
text = path.read_text()
needle = "let highScore = 0;\n"
if needle not in text:
    raise SystemExit("highScore declaration not found")
replacement = 'let highScore = parseInt(localStorage.getItem("stackOverflownHighScore")) || 0;\n'
path.write_text(text.replace(needle, replacement, 1))
PY
git add src/index.js
git commit -m "Add loading of stored high score"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/index.js")
text = path.read_text()
pattern = re.compile(
    r'function updateScore\(\) \{\s*'
    r'document\.getElementById\("score"\)\.textContent = score;\s*'
    r'\}',
    re.S,
)
replacement = '''function updateScore() {
  document.getElementById("score").textContent = score;

  // Update high score if current score exceeds it
  if (score > highScore) {
    highScore = score;
    document.getElementById("high-score").textContent = highScore;
    localStorage.setItem("stackOverflownHighScore", highScore);
  }
}'''
new_text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("updateScore function not found")
path.write_text(new_text)
PY
git add src/index.js
git commit -m "Add logic to keep track of highest score"

git checkout main
git merge --no-ff fix-incomplete-high-score -m "Fix high score tracker"
git branch -D fix-incomplete-high-score

# Second branch, then a real merge commit so the post-merge payload contains
# all required commit messages.
git checkout -b add-level-counter

python3 - <<'PY'
from pathlib import Path

path = Path("src/index.html")
text = path.read_text()
needle = '<div class="score" id="score">0</div>'
if needle not in text:
    raise SystemExit("score element not found")
addition = needle + '\n          <h3>Level</h3>\n          <div class="score" id="level">1</div>'
path.write_text(text.replace(needle, addition, 1))
PY
git add src/index.html
git commit -m "Add element to display current level"

python3 - <<'PY'
from pathlib import Path

path = Path("src/index.js")
text = path.read_text()
needle = 'let highScore = parseInt(localStorage.getItem("stackOverflownHighScore")) || 0;\n'
if needle not in text:
    raise SystemExit("highScore initializer not found")
path.write_text(text.replace(needle, needle + "let level = 1;\nlet patternsCleared = 0;\n", 1))
PY
git add src/index.js
git commit -m "Add variables for level and clear counter"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/index.js")
text = path.read_text()
pattern = re.compile(r'function checkPatternMatch\(\) \{.*?\n\}', re.S)
replacement = '''function checkPatternMatch() {
  for (let startRow = 0; startRow <= ROWS - PATTERN_SIZE; startRow++) {
    for (let startCol = 0; startCol <= COLS - PATTERN_SIZE; startCol++) {
      if (matchesPattern(startRow, startCol)) {
        clearPattern(startRow, startCol);
        score += 100;
        patternsCleared++;
        if (patternsCleared % 5 === 0) {
          level++;
          dropInterval = Math.max(200, 1000 - (level - 1) * 100);
          document.getElementById("level").textContent = level;
        }
        updateScore();
        setNewTargetPattern();
        return;
      }
    }
  }
}'''
new_text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("checkPatternMatch function not found")
path.write_text(new_text)
PY
git add src/index.js
git commit -m "Add logic to calculate level"

git checkout main
git merge --no-ff add-level-counter -m "Add level counter"
git branch -D add-level-counter

git log --all --graph --oneline
wait_active 429302979 "Step 6" || exit 1

touch "$MARKER"
echo "=== course-run complete $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
